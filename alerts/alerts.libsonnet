{
  local clusterVariableQueryString = if $._config.showMultiCluster then '&var-%(clusterLabel)s={{ $labels.%(clusterLabel)s}}' % $._config else '',
  prometheusAlerts+:: {
    groups+: [
      {
        name: 'external-secrets-operator',
        rules: if $._config.alerts.enabled then std.prune([
          if $._config.alerts.externalSecretSyncErrors.enabled then {
            alert: 'ExternalSecretsOperatorSyncErrors',
            expr: |||
              (
                sum(
                  increase(
                    externalsecret_sync_calls_error{
                      %(esoSelector)s
                    }[%(interval)s]
                  )
                ) by (%(namespaceLabel)s, name)
                /
                sum(
                  increase(
                    externalsecret_sync_calls_total{
                      %(esoSelector)s
                    }[%(interval)s]
                  )
                ) by (%(namespaceLabel)s, name)
                * 100
              ) > %(threshold)s
            ||| % (
              $._config
              {
                interval: $._config.alerts.externalSecretSyncErrors.interval,
                threshold: $._config.alerts.externalSecretSyncErrors.threshold,
              }
            ),
            'for': '5m',
            labels: {
              severity: $._config.alerts.externalSecretSyncErrors.severity,
            },
            annotations: {
              summary: 'External Secrets Operator has a high ExternalSecret sync error rate.',
              description: 'More than %(threshold)s%% of sync calls failed for ExternalSecret {{ $labels.name }} in {{ $labels.%(namespaceLabel)s }} the past %(interval)s.' % (
                $._config.alerts.externalSecretSyncErrors { namespaceLabel: $._config.namespaceLabel }
              ),
              dashboard_url: $._config.dashboardUrls['eso-resources'] + '?var-namespace={{ $labels.%(namespaceLabel)s }}&var-name={{ $labels.name }}' % $._config + clusterVariableQueryString,
            },
          },
          if $._config.alerts.externalSecretNotReady.enabled then {
            alert: 'ExternalSecretsOperatorExternalSecretNotReady',
            expr: |||
              sum(
                externalsecret_status_condition{
                  %(esoSelector)s,
                  condition="Ready",
                  status="False"
                }
              ) by (%(namespaceLabel)s, name, condition, status)
              == 1
            ||| % $._config,
            'for': $._config.alerts.externalSecretNotReady.interval,
            labels: {
              severity: $._config.alerts.externalSecretNotReady.severity,
            },
            annotations: {
              summary: 'External Secrets Operator ExternalSecret is not ready.',
              description: 'ExternalSecret {{ $labels.name }} in {{ $labels.%(namespaceLabel)s }} has not been Ready for the past %(interval)s.' % (
                $._config.alerts.externalSecretNotReady { namespaceLabel: $._config.namespaceLabel }
              ),
              dashboard_url: $._config.dashboardUrls['eso-resources'] + '?var-namespace={{ $labels.%(namespaceLabel)s }}&var-name={{ $labels.name }}' % $._config + clusterVariableQueryString,
            },
          },
          if $._config.alerts.secretStoreNotReady.enabled then {
            alert: 'ExternalSecretsOperatorSecretStoreNotReady',
            expr: |||
              sum(
                secretstore_status_condition{
                  %(esoSelector)s,
                  condition="Ready",
                  status="False"
                }
              ) by (%(namespaceLabel)s, name, condition, status)
              == 1
            ||| % $._config,
            'for': $._config.alerts.secretStoreNotReady.interval,
            labels: {
              severity: $._config.alerts.secretStoreNotReady.severity,
            },
            annotations: {
              summary: 'External Secrets Operator SecretStore is not ready.',
              description: 'SecretStore {{ $labels.name }} in {{ $labels.%(namespaceLabel)s }} has not been Ready for the past %(interval)s.' % (
                $._config.alerts.secretStoreNotReady { namespaceLabel: $._config.namespaceLabel }
              ),
              dashboard_url: $._config.dashboardUrls['eso-resources'] + '?var-secret_store_namespace={{ $labels.%(namespaceLabel)s }}&var-secret_store_name={{ $labels.name }}' % $._config + clusterVariableQueryString,
            },
          },
          if $._config.alerts.clusterSecretStoreNotReady.enabled then {
            alert: 'ExternalSecretsOperatorClusterSecretStoreNotReady',
            expr: |||
              sum(
                clustersecretstore_status_condition{
                  %(esoSelector)s,
                  condition="Ready",
                  status="False"
                }
              ) by (name, condition, status)
              == 1
            ||| % $._config,
            'for': $._config.alerts.clusterSecretStoreNotReady.interval,
            labels: {
              severity: $._config.alerts.clusterSecretStoreNotReady.severity,
            },
            annotations: {
              summary: 'External Secrets Operator ClusterSecretStore is not ready.',
              description: 'ClusterSecretStore {{ $labels.name }} has not been Ready for the past %(interval)s.' % $._config.alerts.clusterSecretStoreNotReady,
              dashboard_url: $._config.dashboardUrls['eso-resources'] + '?var-secret_store_name={{ $labels.name }}' + clusterVariableQueryString,
            },
          },
          if $._config.alerts.pushSecretNotReady.enabled then {
            alert: 'ExternalSecretsOperatorPushSecretNotReady',
            expr: |||
              sum(
                pushsecret_status_condition{
                  %(esoSelector)s,
                  condition="Ready",
                  status="False"
                }
              ) by (%(namespaceLabel)s, name, condition, status)
              == 1
            ||| % $._config,
            'for': $._config.alerts.pushSecretNotReady.interval,
            labels: {
              severity: $._config.alerts.pushSecretNotReady.severity,
            },
            annotations: {
              summary: 'External Secrets Operator PushSecret is not ready.',
              description: 'PushSecret {{ $labels.name }} in {{ $labels.%(namespaceLabel)s }} has not been Ready for the past %(interval)s.' % (
                $._config.alerts.pushSecretNotReady { namespaceLabel: $._config.namespaceLabel }
              ),
              dashboard_url: $._config.dashboardUrls['eso-resources'] + '?var-push_secret_namespace={{ $labels.%(namespaceLabel)s }}&var-push_secret_name={{ $labels.name }}' % $._config + clusterVariableQueryString,
            },
          },
          if $._config.alerts.providerApiErrorRate.enabled then {
            alert: 'ExternalSecretsOperatorProviderApiHighErrorRate',
            expr: |||
              (
                sum(
                  increase(
                    externalsecret_provider_api_calls_count{
                      %(esoSelector)s,
                      status="error"
                    }[%(interval)s]
                  )
                ) by (provider)
                /
                sum(
                  increase(
                    externalsecret_provider_api_calls_count{
                      %(esoSelector)s
                    }[%(interval)s]
                  )
                ) by (provider)
                * 100
              ) > %(threshold)s
            ||| % (
              $._config
              {
                interval: $._config.alerts.providerApiErrorRate.interval,
                threshold: $._config.alerts.providerApiErrorRate.threshold,
              }
            ),
            'for': '5m',
            labels: {
              severity: $._config.alerts.providerApiErrorRate.severity,
            },
            annotations: {
              summary: 'External Secrets Operator has a high provider API error rate.',
              description: 'More than %(threshold)s%% of API calls to provider {{ $labels.provider }} failed the past %(interval)s.' % $._config.alerts.providerApiErrorRate,
              dashboard_url: $._config.dashboardUrls['eso-overview'] + clusterVariableQueryString,
            },
          },
        ]),
      },
    ],
  },
}
