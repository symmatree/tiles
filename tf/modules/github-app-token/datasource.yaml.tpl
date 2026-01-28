apiVersion: 1
datasources:
  - name: GitHub
    uid: github
    type: grafana-github-datasource
    access: proxy
    url: https://api.github.com
    isDefault: false
    jsonData:
      githubUrl: https://github.com
    secureJsonData:
      token: ${token}
