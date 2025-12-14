{
  item: {
    new:: function(name, itemPath) {
      apiVersion: 'onepassword.com/v1',
      kind: 'OnePasswordItem',
      metadata: {
        name: name,
      },
      type: 'Opaque',
      spec: {
        itemPath: itemPath,
      },
    },
  },
}
