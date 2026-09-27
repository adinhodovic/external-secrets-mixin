{
  _config+:: {
    local this = self,

    esoSelector: 'job=~".*external-secrets.*"',

    // Default datasource name
    datasourceName: 'default',

    // Opt-in to multiCluster dashboards by overriding this and the clusterLabel.
    showMultiCluster: false,
    clusterLabel: 'cluster',

    // With honor_labels: false (the common default), the resource's own "namespace" label is
    // overwritten by the scrape target's and survives as "exported_namespace" instead.
    // Override to 'namespace' if your setup scrapes with honor_labels: true.
    namespaceLabel: 'exported_namespace',

    grafanaUrl: 'https://grafana.com',

    dashboardIds: {
      'eso-overview': 'eso-overview-skj2',
      'eso-resources': 'eso-resources-skj2',
    },
    dashboardUrls: {
      'eso-overview': '%s/d/%s/eso-overview' % [this.grafanaUrl, this.dashboardIds['eso-overview']],
      'eso-resources': '%s/d/%s/eso-resources' % [this.grafanaUrl, this.dashboardIds['eso-resources']],
    },

    tags: ['external-secrets', 'eso-mixin', 'kubernetes'],

    // External Secrets Operator alert configuration
    alerts: {
      enabled: true,

      externalSecretSyncErrors: {
        enabled: true,
        severity: 'warning',
        interval: '15m',
        threshold: '5',  // percent
      },

      externalSecretNotReady: {
        enabled: true,
        severity: 'warning',
        interval: '15m',
      },

      clusterExternalSecretNotReady: {
        enabled: true,
        severity: 'warning',
        interval: '15m',
      },

      secretStoreNotReady: {
        enabled: true,
        severity: 'warning',
        interval: '15m',
      },

      clusterSecretStoreNotReady: {
        enabled: true,
        severity: 'warning',
        interval: '15m',
      },

      pushSecretNotReady: {
        enabled: true,
        severity: 'warning',
        interval: '15m',
      },

      clusterPushSecretNotReady: {
        enabled: true,
        severity: 'warning',
        interval: '15m',
      },

      providerApiErrorRate: {
        enabled: true,
        severity: 'warning',
        interval: '15m',
        threshold: '5',  // percent
      },
    },

    // Custom annotations to display in graphs
    annotation: {
      enabled: false,
      name: 'Custom Annotation',
      tags: [],
      datasource: '-- Grafana --',
      iconColor: 'blue',
      type: 'tags',
    },
  },
}
