package main

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/client-go/dynamic"
	"k8s.io/client-go/rest"
	"k8s.io/kubectl/pkg/polymorphichelpers"
)

// fieldManager owns the restart annotation. Argo CD applies these workloads with
// server-side apply, so the annotation belongs to a manager Argo does not own and
// does not read as drift.
const fieldManager = "argo-tag-watcher"

// restartAnnotation is the one `kubectl rollout restart` writes.
const restartAnnotation = "kubectl.kubernetes.io/restartedAt"

// rollable is one workload kind the watcher can restart. All three carry the same
// spec.selector and spec.template shape, so they need no per-kind handling here;
// kubectl's helpers supply what does differ, namely how to read rollout status and
// how to build the restart patch.
type rollable struct {
	kind string
	gvr  schema.GroupVersionResource
}

var rollables = []rollable{
	{"Deployment", schema.GroupVersionResource{Group: "apps", Version: "v1", Resource: "deployments"}},
	{"StatefulSet", schema.GroupVersionResource{Group: "apps", Version: "v1", Resource: "statefulsets"}},
	{"DaemonSet", schema.GroupVersionResource{Group: "apps", Version: "v1", Resource: "daemonsets"}},
}

type k8sRoller struct {
	dyn dynamic.Interface
}

func newK8sRoller() (*k8sRoller, error) {
	restCfg, err := rest.InClusterConfig()
	if err != nil {
		return nil, err
	}
	dyn, err := dynamic.NewForConfig(restCfg)
	if err != nil {
		return nil, err
	}
	return &k8sRoller{dyn: dyn}, nil
}

// ListWorkloads returns the opted-in workloads in every namespace.
func (k *k8sRoller) ListWorkloads(ctx context.Context) ([]Workload, error) {
	var out []Workload
	for _, r := range rollables {
		list, err := k.dyn.Resource(r.gvr).Namespace(metav1.NamespaceAll).List(ctx, metav1.ListOptions{})
		if err != nil {
			return nil, fmt.Errorf("listing %s: %w", r.gvr.Resource, err)
		}
		for _, item := range list.Items {
			if item.GetAnnotations()[RollAnnotation] != "true" {
				continue
			}
			w, err := workloadFrom(r.kind, item)
			if err != nil {
				return nil, fmt.Errorf("reading %s %s/%s: %w", r.kind, item.GetNamespace(), item.GetName(), err)
			}
			out = append(out, w)
		}
	}
	return out, nil
}

// workloadFrom reads the parts of a workload the watcher compares on. Settled
// comes from kubectl's rollout-status viewer -- the same check `kubectl rollout
// status` reports -- rather than a per-kind reading of replica counts here.
func workloadFrom(kind string, obj unstructured.Unstructured) (Workload, error) {
	viewer, err := polymorphichelpers.StatusViewerFor(schema.GroupKind{Group: "apps", Kind: kind})
	if err != nil {
		return Workload{}, err
	}
	_, settled, err := viewer.Status(&obj, 0)
	if err != nil {
		return Workload{}, err
	}

	selector, err := selectorOf(obj)
	if err != nil {
		return Workload{}, err
	}
	containers, err := containersOf(obj)
	if err != nil {
		return Workload{}, err
	}
	return Workload{
		Kind:       kind,
		Namespace:  obj.GetNamespace(),
		Name:       obj.GetName(),
		Selector:   selector,
		Containers: containers,
		Settled:    settled,
	}, nil
}

func selectorOf(obj unstructured.Unstructured) (string, error) {
	raw, found, err := unstructured.NestedMap(obj.Object, "spec", "selector")
	if err != nil || !found {
		return "", fmt.Errorf("no spec.selector: %w", err)
	}
	var selector metav1.LabelSelector
	if err := runtime.DefaultUnstructuredConverter.FromUnstructured(raw, &selector); err != nil {
		return "", err
	}
	s, err := metav1.LabelSelectorAsSelector(&selector)
	if err != nil {
		return "", err
	}
	return s.String(), nil
}

func containersOf(obj unstructured.Unstructured) (map[string]string, error) {
	raw, found, err := unstructured.NestedSlice(obj.Object, "spec", "template", "spec", "containers")
	if err != nil || !found {
		return nil, fmt.Errorf("no spec.template.spec.containers: %w", err)
	}
	out := map[string]string{}
	for _, c := range raw {
		container, ok := c.(map[string]any)
		if !ok {
			continue
		}
		name, _ := container["name"].(string)
		image, _ := container["image"].(string)
		if name != "" && image != "" {
			out[name] = image
		}
	}
	return out, nil
}

// ListPods returns the pods that are actually running the workload. Terminal and
// terminating pods are dropped: a Completed or Error pod sticks around holding
// whatever digest it had when it died -- there are months-old ones in the cluster
// -- and comparing against those is a permanent, meaningless mismatch.
func (k *k8sRoller) ListPods(ctx context.Context, namespace, selector string) ([]Pod, error) {
	podGVR := schema.GroupVersionResource{Version: "v1", Resource: "pods"}
	list, err := k.dyn.Resource(podGVR).Namespace(namespace).List(ctx, metav1.ListOptions{LabelSelector: selector})
	if err != nil {
		return nil, fmt.Errorf("listing pods in %s: %w", namespace, err)
	}
	var out []Pod
	for _, item := range list.Items {
		if item.GetDeletionTimestamp() != nil {
			continue
		}
		phase, _, _ := unstructured.NestedString(item.Object, "status", "phase")
		if phase == "Succeeded" || phase == "Failed" {
			continue
		}
		statuses, _, _ := unstructured.NestedSlice(item.Object, "status", "containerStatuses")
		ids := map[string]string{}
		for _, s := range statuses {
			status, ok := s.(map[string]any)
			if !ok {
				continue
			}
			name, _ := status["name"].(string)
			imageID, _ := status["imageID"].(string)
			if d := digestFromImageID(imageID); name != "" && d != "" {
				ids[name] = d
			}
		}
		out = append(out, Pod{Name: item.GetName(), ImageIDs: ids})
	}
	return out, nil
}

// Restart stamps the pod template with a fresh restart time -- the same
// kubectl.kubernetes.io/restartedAt `kubectl rollout restart` uses, which is what
// makes the workload's controller roll its pods.
//
// Written out rather than taken from kubectl's polymorphichelpers.ObjectRestarterFn:
// that one type-switches on typed objects, so it cannot take what the dynamic
// client returns, and it sends the whole object as a strategic merge patch. All we
// need to set is one annotation, and a patch that names only it keeps this field
// manager off every other field of a workload Argo owns.
func (k *k8sRoller) Restart(ctx context.Context, w Workload) error {
	gvr, err := gvrFor(w.Kind)
	if err != nil {
		return err
	}
	patch, err := json.Marshal(map[string]any{"spec": map[string]any{"template": map[string]any{
		"metadata": map[string]any{"annotations": map[string]string{
			restartAnnotation: time.Now().UTC().Format(time.RFC3339),
		}},
	}}})
	if err != nil {
		return err
	}
	_, err = k.dyn.Resource(gvr).Namespace(w.Namespace).Patch(
		ctx, w.Name, types.MergePatchType, patch,
		metav1.PatchOptions{FieldManager: fieldManager})
	return err
}

func gvrFor(kind string) (schema.GroupVersionResource, error) {
	for _, r := range rollables {
		if r.kind == kind {
			return r.gvr, nil
		}
	}
	return schema.GroupVersionResource{}, fmt.Errorf("unknown workload kind %q", kind)
}
