package main

import (
	"context"
	"fmt"
	"time"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"
)

// fieldManager owns the restart annotation. Argo CD applies these workloads with
// server-side apply, so the annotation belongs to a manager Argo does not own and
// does not read as drift.
const fieldManager = "argo-tag-watcher"

// restartAnnotation is the one `kubectl rollout restart` uses. Same mechanism,
// same annotation: a change to the pod template is what makes the controller roll.
const restartAnnotation = "kubectl.kubernetes.io/restartedAt"

type k8sRoller struct {
	cs kubernetes.Interface
}

func newK8sRoller() (*k8sRoller, error) {
	restCfg, err := rest.InClusterConfig()
	if err != nil {
		return nil, err
	}
	cs, err := kubernetes.NewForConfig(restCfg)
	if err != nil {
		return nil, err
	}
	return &k8sRoller{cs: cs}, nil
}

// ListWorkloads returns the opted-in Deployments, StatefulSets and DaemonSets in
// every namespace.
func (k *k8sRoller) ListWorkloads(ctx context.Context) ([]Workload, error) {
	var out []Workload

	deployments, err := k.cs.AppsV1().Deployments(metav1.NamespaceAll).List(ctx, metav1.ListOptions{})
	if err != nil {
		return nil, fmt.Errorf("listing deployments: %w", err)
	}
	for _, d := range deployments.Items {
		if !optedIn(d.Annotations) {
			continue
		}
		st := d.Status
		out = append(out, workload("Deployment", d.ObjectMeta, d.Spec.Selector, d.Spec.Template,
			st.ObservedGeneration == d.Generation &&
				st.UpdatedReplicas == st.Replicas &&
				st.UnavailableReplicas == 0))
	}

	statefulSets, err := k.cs.AppsV1().StatefulSets(metav1.NamespaceAll).List(ctx, metav1.ListOptions{})
	if err != nil {
		return nil, fmt.Errorf("listing statefulsets: %w", err)
	}
	for _, s := range statefulSets.Items {
		if !optedIn(s.Annotations) {
			continue
		}
		st := s.Status
		out = append(out, workload("StatefulSet", s.ObjectMeta, s.Spec.Selector, s.Spec.Template,
			st.ObservedGeneration == s.Generation &&
				st.CurrentRevision == st.UpdateRevision &&
				st.ReadyReplicas == st.Replicas))
	}

	daemonSets, err := k.cs.AppsV1().DaemonSets(metav1.NamespaceAll).List(ctx, metav1.ListOptions{})
	if err != nil {
		return nil, fmt.Errorf("listing daemonsets: %w", err)
	}
	for _, d := range daemonSets.Items {
		if !optedIn(d.Annotations) {
			continue
		}
		st := d.Status
		out = append(out, workload("DaemonSet", d.ObjectMeta, d.Spec.Selector, d.Spec.Template,
			st.ObservedGeneration == d.Generation &&
				st.UpdatedNumberScheduled == st.DesiredNumberScheduled &&
				st.NumberUnavailable == 0))
	}
	return out, nil
}

func optedIn(annotations map[string]string) bool {
	return annotations[RollAnnotation] == "true"
}

func workload(kind string, meta metav1.ObjectMeta, selector *metav1.LabelSelector, tmpl corev1.PodTemplateSpec, settled bool) Workload {
	containers := map[string]string{}
	for _, c := range tmpl.Spec.Containers {
		containers[c.Name] = c.Image
	}
	sel, err := metav1.LabelSelectorAsSelector(selector)
	selectorString := ""
	if err == nil {
		selectorString = sel.String()
	}
	return Workload{
		Kind:       kind,
		Namespace:  meta.Namespace,
		Name:       meta.Name,
		Selector:   selectorString,
		Containers: containers,
		Settled:    settled,
	}
}

// ListPods returns the pods that are actually running the workload. Terminal and
// terminating pods are dropped: a Completed or Error pod sticks around holding
// whatever digest it had when it died -- there are several months-old ones in the
// cluster -- and comparing against those is a permanent, meaningless mismatch.
func (k *k8sRoller) ListPods(ctx context.Context, namespace, selector string) ([]Pod, error) {
	list, err := k.cs.CoreV1().Pods(namespace).List(ctx, metav1.ListOptions{LabelSelector: selector})
	if err != nil {
		return nil, fmt.Errorf("listing pods in %s: %w", namespace, err)
	}
	var out []Pod
	for _, p := range list.Items {
		if p.DeletionTimestamp != nil {
			continue
		}
		if p.Status.Phase == corev1.PodSucceeded || p.Status.Phase == corev1.PodFailed {
			continue
		}
		ids := map[string]string{}
		for _, cs := range p.Status.ContainerStatuses {
			if d := digestFromImageID(cs.ImageID); d != "" {
				ids[cs.Name] = d
			}
		}
		out = append(out, Pod{Name: p.Name, ImageIDs: ids})
	}
	return out, nil
}

// Restart stamps the pod template with a fresh restart time, which is what makes
// the workload's controller roll its pods.
func (k *k8sRoller) Restart(ctx context.Context, w Workload) error {
	patch := []byte(fmt.Sprintf(
		`{"spec":{"template":{"metadata":{"annotations":{%q:%q}}}}}`,
		restartAnnotation, time.Now().UTC().Format(time.RFC3339)))
	opts := metav1.PatchOptions{FieldManager: fieldManager}

	var err error
	switch w.Kind {
	case "Deployment":
		_, err = k.cs.AppsV1().Deployments(w.Namespace).Patch(ctx, w.Name, types.MergePatchType, patch, opts)
	case "StatefulSet":
		_, err = k.cs.AppsV1().StatefulSets(w.Namespace).Patch(ctx, w.Name, types.MergePatchType, patch, opts)
	case "DaemonSet":
		_, err = k.cs.AppsV1().DaemonSets(w.Namespace).Patch(ctx, w.Name, types.MergePatchType, patch, opts)
	default:
		return fmt.Errorf("unknown workload kind %q", w.Kind)
	}
	return err
}
