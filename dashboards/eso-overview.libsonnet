local mixinUtils = import 'github.com/adinhodovic/mixin-utils/utils.libsonnet';
local g = import 'github.com/grafana/grafonnet/gen/grafonnet-latest/main.libsonnet';
local util = import 'util.libsonnet';

local dashboard = g.dashboard;
local row = g.panel.row;
local grid = g.util.grid;

local tablePanel = g.panel.table;

// Table
local tbStandardOptions = tablePanel.standardOptions;
local tbQueryOptions = tablePanel.queryOptions;
local tbPanelOptions = tablePanel.panelOptions;

{
  local dashboardName = 'eso-overview',
  grafanaDashboards+:: {
    ['%s.json' % dashboardName]:

      local defaultVariables = util.variables($._config);

      // Overview is a fleet-wide health summary: only namespace and provider are filterable,
      // there's no per-resource-name drill-down here (that's what the Resources dashboard is for).
      local variables = [
        defaultVariables.datasource,
        defaultVariables.cluster,
        defaultVariables.job,
        defaultVariables.namespace,
        defaultVariables.provider,
      ];

      local defaultFilters = util.filters($._config);
      local namespaceLabel = defaultFilters.namespaceLabel;

      // Shared shapes behind the per-CRD stats and tables below: a distinct-entity count, the
      // Ready-condition percentage, and the "which ones are currently failing" list. Each CRD
      // kind only differs in its metric name, filter fragment and grouping labels.
      local namespacedBy = '%s, name' % namespaceLabel;
      local clusterBy = 'name';

      local countBy(metricName, filterExpr, byClause) = |||
        count(
          count(
            %(metricName)s{
              %(filterExpr)s
            }
          ) by (%(byClause)s)
        )
      ||| % { metricName: metricName, filterExpr: filterExpr, byClause: byClause };

      local readyPercent(metricName, filterExpr) = |||
        sum(
          %(metricName)s{
            %(filterExpr)s,
            condition="Ready",
            status="True"
          }
        )
        /
        sum(
          %(metricName)s{
            %(filterExpr)s,
            condition="Ready"
          }
        )
        * 100
      ||| % { metricName: metricName, filterExpr: filterExpr };

      local notReadyQuery(metricName, filterExpr, byClause) = |||
        sum(
          %(metricName)s{
            %(filterExpr)s,
            condition="Ready",
            status="False"
          }
        ) by (%(byClause)s, condition, status)
        == 1
      ||| % { metricName: metricName, filterExpr: filterExpr, byClause: byClause };

      local queries = {
        // Counts
        externalSecretsCount: countBy('externalsecret_status_condition', defaultFilters.namespaced, namespacedBy),
        clusterExternalSecretsCount: countBy('clusterexternalsecret_status_condition', defaultFilters.default, clusterBy),
        secretStoresCount: countBy('secretstore_status_condition', defaultFilters.namespaced, namespacedBy),
        clusterSecretStoresCount: countBy('clustersecretstore_status_condition', defaultFilters.default, clusterBy),
        pushSecretsCount: countBy('pushsecret_status_condition', defaultFilters.namespaced, namespacedBy),
        clusterPushSecretsCount: countBy('clusterpushsecret_status_condition', defaultFilters.default, clusterBy),
        providersCount: countBy('externalsecret_provider_api_calls_count', defaultFilters.providerRuntime, 'provider'),

        // Distinct namespaces holding at least one of ESO's namespaced CRDs - "or" between
        // the raw metrics unions whichever kinds currently have data.
        namespacesCount: |||
          count(
            count(
              externalsecret_status_condition{%(namespaced)s}
              or
              secretstore_status_condition{%(namespaced)s}
              or
              pushsecret_status_condition{%(namespaced)s}
            ) by (%(namespaceLabel)s)
          )
        ||| % defaultFilters,

        // Fleet-wide totals across all three CRD families. "or" between the raw metrics
        // (rather than adding pre-aggregated per-kind counts) unions whichever of the five
        // sources currently has data, so these stay correct even when a whole CRD family
        // (e.g. PushSecret) has zero instances - a plain "+" would inner-join on labels and
        // silently produce no data at all instead of falling back to what does exist.
        totalResourcesCount: |||
          count(
            count(
              externalsecret_status_condition{%(namespaced)s}
              or
              clusterexternalsecret_status_condition{%(default)s}
              or
              secretstore_status_condition{%(namespaced)s}
              or
              clustersecretstore_status_condition{%(default)s}
              or
              pushsecret_status_condition{%(namespaced)s}
              or
              clusterpushsecret_status_condition{%(default)s}
            ) by (%(namespaceLabel)s, name)
          )
        ||| % defaultFilters,

        totalReadyPercent: |||
          sum(
            externalsecret_status_condition{%(namespaced)s, condition="Ready", status="True"}
            or
            clusterexternalsecret_status_condition{%(default)s, condition="Ready", status="True"}
            or
            secretstore_status_condition{%(namespaced)s, condition="Ready", status="True"}
            or
            clustersecretstore_status_condition{%(default)s, condition="Ready", status="True"}
            or
            pushsecret_status_condition{%(namespaced)s, condition="Ready", status="True"}
            or
            clusterpushsecret_status_condition{%(default)s, condition="Ready", status="True"}
          )
          /
          sum(
            externalsecret_status_condition{%(namespaced)s, condition="Ready"}
            or
            clusterexternalsecret_status_condition{%(default)s, condition="Ready"}
            or
            secretstore_status_condition{%(namespaced)s, condition="Ready"}
            or
            clustersecretstore_status_condition{%(default)s, condition="Ready"}
            or
            pushsecret_status_condition{%(namespaced)s, condition="Ready"}
            or
            clusterpushsecret_status_condition{%(default)s, condition="Ready"}
          )
          * 100
        ||| % defaultFilters,

        totalNotReadyCount: |||
          sum(
            externalsecret_status_condition{%(namespaced)s, condition="Ready", status="False"}
            or
            clusterexternalsecret_status_condition{%(default)s, condition="Ready", status="False"}
            or
            secretstore_status_condition{%(namespaced)s, condition="Ready", status="False"}
            or
            clustersecretstore_status_condition{%(default)s, condition="Ready", status="False"}
            or
            pushsecret_status_condition{%(namespaced)s, condition="Ready", status="False"}
            or
            clusterpushsecret_status_condition{%(default)s, condition="Ready", status="False"}
          )
        ||| % defaultFilters,

        // Ready percentages
        externalSecretsReadyPercent: readyPercent('externalsecret_status_condition', defaultFilters.namespaced),
        clusterExternalSecretReadyPercent: readyPercent('clusterexternalsecret_status_condition', defaultFilters.default),
        secretStoreReadyPercent: readyPercent('secretstore_status_condition', defaultFilters.namespaced),
        clusterSecretStoreReadyPercent: readyPercent('clustersecretstore_status_condition', defaultFilters.default),
        pushSecretReadyPercent: readyPercent('pushsecret_status_condition', defaultFilters.namespaced),
        clusterPushSecretReadyPercent: readyPercent('clusterpushsecret_status_condition', defaultFilters.default),

        syncCallsTotalRate: |||
          sum(
            rate(
              externalsecret_sync_calls_total{
                %(namespaced)s
              }[$__rate_interval]
            )
          )
        ||| % defaultFilters,

        syncCallsErrorRate: |||
          sum(
            rate(
              externalsecret_sync_calls_error{
                %(namespaced)s
              }[$__rate_interval]
            )
          )
        ||| % defaultFilters,

        providerApiErrorRate: |||
          sum(
            rate(
              externalsecret_provider_api_calls_count{
                %(providerRuntime)s,
                status="error"
              }[$__rate_interval]
            )
          )
          /
          sum(
            rate(
              externalsecret_provider_api_calls_count{
                %(providerRuntime)s
              }[$__rate_interval]
            )
          )
          * 100
        ||| % defaultFilters,

        providerApiCallRateTotal: |||
          sum(
            rate(
              externalsecret_provider_api_calls_count{
                %(providerRuntime)s
              }[$__rate_interval]
            )
          )
        ||| % defaultFilters,

        // Count of providers with at least one failed call in the current rate window -
        // distinct from providerApiErrorRate (the overall failure percentage): this says how
        // widespread the failures are, not just how severe.
        providersWithErrorsCount: |||
          count(
            count(
              increase(
                externalsecret_provider_api_calls_count{
                  %(providerRuntime)s,
                  status="error"
                }[$__rate_interval]
              ) > 0
            ) by (provider)
          )
        ||| % defaultFilters,

        // Breakdown by status/provider/namespace - never by individual resource name.
        externalSecretsByReadyStatus: |||
          sum(
            externalsecret_status_condition{
              %(namespaced)s,
              condition="Ready"
            }
          ) by (status)
        ||| % defaultFilters,

        providerApiCallRateByProvider: |||
          topk(20,
            sum(
              rate(
                externalsecret_provider_api_calls_count{
                  %(providerRuntime)s
                }[$__rate_interval]
              )
            ) by (provider)
          )
        ||| % defaultFilters,

        // Not ready - lists the individual offending resources, this is a "what's broken"
        // list rather than a per-resource filter/legend grouping.
        notReadyExternalSecrets: notReadyQuery('externalsecret_status_condition', defaultFilters.namespaced, namespacedBy),
        notReadyClusterExternalSecrets: notReadyQuery('clusterexternalsecret_status_condition', defaultFilters.default, clusterBy),
        notReadySecretStores: notReadyQuery('secretstore_status_condition', defaultFilters.namespaced, namespacedBy),
        notReadyClusterSecretStores: notReadyQuery('clustersecretstore_status_condition', defaultFilters.default, clusterBy),
        notReadyPushSecrets: notReadyQuery('pushsecret_status_condition', defaultFilters.namespaced, namespacedBy),
        notReadyClusterPushSecrets: notReadyQuery('clusterpushsecret_status_condition', defaultFilters.default, clusterBy),
      };

      // Every "Not Ready" table below is the same shape: a Name (+ Namespace, for namespaced
      // CRDs) column, a boolean "Not Ready" column, and a link back to the Resources dashboard
      // pre-filtered to that resource.
      local notReadyTablePanel(title, description, query, namespaced, linkTitle, linkUrl) =
        mixinUtils.dashboards.tablePanel(
          title,
          'short',
          query,
          description=description,
          transformations=[
            tbQueryOptions.transformation.withId('organize') +
            tbQueryOptions.transformation.withOptions({
              renameByName: (if namespaced then { [namespaceLabel]: 'Namespace' } else {}) + {
                name: 'Name',
                Value: 'Not Ready',
              },
              excludeByName: {
                Time: true,
              },
            }),
          ],
        ) +
        tbStandardOptions.withLinks([
          tbPanelOptions.link.withTitle(linkTitle) +
          tbPanelOptions.link.withType('dashboard') +
          tbPanelOptions.link.withUrl(linkUrl) +
          tbPanelOptions.link.withTargetBlank(true),
        ]);

      local panels = {

        // Fleet-wide totals
        totalResourcesCountStat:
          mixinUtils.dashboards.statPanel(
            'Total Resources',
            'short',
            queries.totalResourcesCount,
            description='Total number of ExternalSecrets, SecretStores (incl. ClusterSecretStores) and PushSecrets (incl. ClusterPushSecrets) currently being monitored.',
          ),

        totalReadyPercentStat:
          mixinUtils.dashboards.statPanel(
            'Overall Ready',
            'percent',
            queries.totalReadyPercent,
            description='Percentage of all ESO-managed resources across all three CRD families currently reporting Ready=True.',
            steps=[
              tbStandardOptions.threshold.step.withValue(0) +
              tbStandardOptions.threshold.step.withColor('red'),
              tbStandardOptions.threshold.step.withValue(99) +
              tbStandardOptions.threshold.step.withColor('yellow'),
              tbStandardOptions.threshold.step.withValue(100) +
              tbStandardOptions.threshold.step.withColor('green'),
            ],
          ),

        totalNotReadyCountStat:
          mixinUtils.dashboards.statPanel(
            'Total Not Ready',
            'short',
            queries.totalNotReadyCount,
            description='Total number of resources across all three CRD families currently reporting Ready=False. See the per-CRD rows below for which ones.',
            steps=[
              tbStandardOptions.threshold.step.withValue(0) +
              tbStandardOptions.threshold.step.withColor('green'),
              tbStandardOptions.threshold.step.withValue(1) +
              tbStandardOptions.threshold.step.withColor('red'),
            ],
          ),

        namespacesCountStat:
          mixinUtils.dashboards.statPanel(
            'Namespaces',
            'short',
            queries.namespacesCount,
            description='Distinct namespaces containing at least one ExternalSecret, SecretStore or PushSecret.',
          ),

        // Summary
        externalSecretsCountStat:
          mixinUtils.dashboards.statPanel(
            'External Secrets',
            'short',
            queries.externalSecretsCount,
            description='Total number of ExternalSecret resources currently being monitored.',
          ),

        externalSecretsReadyPercentStat:
          mixinUtils.dashboards.statPanel(
            'External Secrets Ready',
            'percent',
            queries.externalSecretsReadyPercent,
            description='Percentage of ExternalSecrets currently reporting Ready=True. Values below 100% mean secrets are failing to sync - see the Not Ready table below.',
            steps=[
              tbStandardOptions.threshold.step.withValue(0) +
              tbStandardOptions.threshold.step.withColor('red'),
              tbStandardOptions.threshold.step.withValue(99) +
              tbStandardOptions.threshold.step.withColor('yellow'),
              tbStandardOptions.threshold.step.withValue(100) +
              tbStandardOptions.threshold.step.withColor('green'),
            ],
          ),

        clusterExternalSecretsCountStat:
          mixinUtils.dashboards.statPanel(
            'Cluster External Secrets',
            'short',
            queries.clusterExternalSecretsCount,
            description='Total number of ClusterExternalSecrets currently being monitored.',
          ),

        clusterExternalSecretReadyPercentStat:
          mixinUtils.dashboards.statPanel(
            'Cluster External Secrets Ready',
            'percent',
            queries.clusterExternalSecretReadyPercent,
            description='Percentage of ClusterExternalSecrets currently reporting Ready=True.',
            steps=[
              tbStandardOptions.threshold.step.withValue(0) +
              tbStandardOptions.threshold.step.withColor('red'),
              tbStandardOptions.threshold.step.withValue(99) +
              tbStandardOptions.threshold.step.withColor('yellow'),
              tbStandardOptions.threshold.step.withValue(100) +
              tbStandardOptions.threshold.step.withColor('green'),
            ],
          ),

        secretStoresCountStat:
          mixinUtils.dashboards.statPanel(
            'Secret Stores',
            'short',
            queries.secretStoresCount,
            description='Total number of namespaced SecretStores currently being monitored.',
          ),

        clusterSecretStoresCountStat:
          mixinUtils.dashboards.statPanel(
            'Cluster Secret Stores',
            'short',
            queries.clusterSecretStoresCount,
            description='Total number of ClusterSecretStores currently being monitored.',
          ),

        secretStoreReadyPercentStat:
          mixinUtils.dashboards.statPanel(
            'Secret Stores Ready',
            'percent',
            queries.secretStoreReadyPercent,
            description='Percentage of SecretStores currently reporting Ready=True. Non-100% values usually mean invalid provider credentials or an unreachable provider endpoint.',
            steps=[
              tbStandardOptions.threshold.step.withValue(0) +
              tbStandardOptions.threshold.step.withColor('red'),
              tbStandardOptions.threshold.step.withValue(99) +
              tbStandardOptions.threshold.step.withColor('yellow'),
              tbStandardOptions.threshold.step.withValue(100) +
              tbStandardOptions.threshold.step.withColor('green'),
            ],
          ),

        clusterSecretStoreReadyPercentStat:
          mixinUtils.dashboards.statPanel(
            'Cluster Secret Stores Ready',
            'percent',
            queries.clusterSecretStoreReadyPercent,
            description='Percentage of ClusterSecretStores currently reporting Ready=True.',
            steps=[
              tbStandardOptions.threshold.step.withValue(0) +
              tbStandardOptions.threshold.step.withColor('red'),
              tbStandardOptions.threshold.step.withValue(99) +
              tbStandardOptions.threshold.step.withColor('yellow'),
              tbStandardOptions.threshold.step.withValue(100) +
              tbStandardOptions.threshold.step.withColor('green'),
            ],
          ),

        pushSecretsCountStat:
          mixinUtils.dashboards.statPanel(
            'Push Secrets',
            'short',
            queries.pushSecretsCount,
            description='Total number of namespaced PushSecrets currently being monitored.',
          ),

        clusterPushSecretsCountStat:
          mixinUtils.dashboards.statPanel(
            'Cluster Push Secrets',
            'short',
            queries.clusterPushSecretsCount,
            description='Total number of ClusterPushSecrets currently being monitored.',
          ),

        pushSecretReadyPercentStat:
          mixinUtils.dashboards.statPanel(
            'Push Secrets Ready',
            'percent',
            queries.pushSecretReadyPercent,
            description='Percentage of PushSecrets currently reporting Ready=True.',
            steps=[
              tbStandardOptions.threshold.step.withValue(0) +
              tbStandardOptions.threshold.step.withColor('red'),
              tbStandardOptions.threshold.step.withValue(99) +
              tbStandardOptions.threshold.step.withColor('yellow'),
              tbStandardOptions.threshold.step.withValue(100) +
              tbStandardOptions.threshold.step.withColor('green'),
            ],
          ),

        clusterPushSecretReadyPercentStat:
          mixinUtils.dashboards.statPanel(
            'Cluster Push Secrets Ready',
            'percent',
            queries.clusterPushSecretReadyPercent,
            description='Percentage of ClusterPushSecrets currently reporting Ready=True.',
            steps=[
              tbStandardOptions.threshold.step.withValue(0) +
              tbStandardOptions.threshold.step.withColor('red'),
              tbStandardOptions.threshold.step.withValue(99) +
              tbStandardOptions.threshold.step.withColor('yellow'),
              tbStandardOptions.threshold.step.withValue(100) +
              tbStandardOptions.threshold.step.withColor('green'),
            ],
          ),

        providersCountStat:
          mixinUtils.dashboards.statPanel(
            'Providers',
            'short',
            queries.providersCount,
            description='Distinct upstream secret provider backends currently in use by ExternalSecrets.',
          ),

        syncCallsTotalRateStat:
          mixinUtils.dashboards.statPanel(
            'Sync Call Rate',
            'reqps',
            queries.syncCallsTotalRate,
            description='Rate of ExternalSecret sync attempts against providers.',
          ),

        syncCallsErrorRateStat:
          mixinUtils.dashboards.statPanel(
            'Sync Error Rate',
            'reqps',
            queries.syncCallsErrorRate,
            description='Rate of failed ExternalSecret sync attempts.',
            steps=[
              tbStandardOptions.threshold.step.withValue(0) +
              tbStandardOptions.threshold.step.withColor('green'),
              tbStandardOptions.threshold.step.withValue(0.01) +
              tbStandardOptions.threshold.step.withColor('red'),
            ],
          ),

        providerApiErrorRateStat:
          mixinUtils.dashboards.statPanel(
            'Provider API Error Rate',
            'percent',
            queries.providerApiErrorRate,
            description='Percentage of upstream secret provider API calls that failed. High values point to provider throttling, expired credentials, or network connectivity issues between ESO and the provider.',
            steps=[
              tbStandardOptions.threshold.step.withValue(0) +
              tbStandardOptions.threshold.step.withColor('green'),
              tbStandardOptions.threshold.step.withValue(1) +
              tbStandardOptions.threshold.step.withColor('yellow'),
              tbStandardOptions.threshold.step.withValue(5) +
              tbStandardOptions.threshold.step.withColor('red'),
            ],
          ),

        providerApiCallRateTotalStat:
          mixinUtils.dashboards.statPanel(
            'Provider API Call Rate',
            'reqps',
            queries.providerApiCallRateTotal,
            description='Combined rate of API calls to all upstream secret providers.',
          ),

        providersWithErrorsCountStat:
          mixinUtils.dashboards.statPanel(
            'Providers with Errors',
            'short',
            queries.providersWithErrorsCount,
            description='Number of distinct provider backends with at least one failed API call right now - shows how widespread a problem is, as opposed to the Provider API Error Rate above, which shows how severe it is.',
            steps=[
              tbStandardOptions.threshold.step.withValue(0) +
              tbStandardOptions.threshold.step.withColor('green'),
              tbStandardOptions.threshold.step.withValue(1) +
              tbStandardOptions.threshold.step.withColor('red'),
            ],
          ),

        externalSecretsByReadyStatusTimeSeries:
          mixinUtils.dashboards.timeSeriesPanel(
            'External Secrets by Ready Status',
            'short',
            queries.externalSecretsByReadyStatus,
            '{{ status }}',
            description='Count of ExternalSecrets by their Ready condition status over time. A rising non-True count needs investigation.',
            stack='normal',
          ),

        providerApiCallRateByProviderTimeSeries:
          mixinUtils.dashboards.timeSeriesPanel(
            'Provider API Call Rate by Provider [Top 20]',
            'reqps',
            queries.providerApiCallRateByProvider,
            '{{ provider }}',
            description='Provider API call rate broken down by the busiest 20 secret provider backends.',
            stack='normal',
          ),

        notReadyExternalSecretsTable: notReadyTablePanel(
          'Not Ready External Secrets',
          'ExternalSecrets currently reporting condition Ready=False.',
          queries.notReadyExternalSecrets,
          true,
          'Go To External Secret',
          '/d/%s/eso-resources?var-namespace=${__data.fields.Namespace}&var-name=${__data.fields.Name}' % $._config.dashboardIds['eso-resources']
        ),

        notReadyClusterExternalSecretsTable: notReadyTablePanel(
          'Not Ready Cluster External Secrets',
          'ClusterExternalSecrets currently reporting condition Ready=False.',
          queries.notReadyClusterExternalSecrets,
          false,
          'Go To External Secret',
          '/d/%s/eso-resources?var-name=${__data.fields.Name}' % $._config.dashboardIds['eso-resources']
        ),

        notReadySecretStoresTable: notReadyTablePanel(
          'Not Ready Secret Stores',
          'SecretStores currently reporting condition Ready=False. Typically means invalid provider credentials or an unreachable provider endpoint.',
          queries.notReadySecretStores,
          true,
          'Go To Secret Store',
          '/d/%s/eso-resources?var-namespace=${__data.fields.Namespace}&var-secret_store_name=${__data.fields.Name}' % $._config.dashboardIds['eso-resources']
        ),

        notReadyClusterSecretStoresTable: notReadyTablePanel(
          'Not Ready Cluster Secret Stores',
          'ClusterSecretStores currently reporting condition Ready=False.',
          queries.notReadyClusterSecretStores,
          false,
          'Go To Secret Store',
          '/d/%s/eso-resources?var-secret_store_name=${__data.fields.Name}' % $._config.dashboardIds['eso-resources']
        ),

        notReadyPushSecretsTable: notReadyTablePanel(
          'Not Ready Push Secrets',
          'PushSecrets currently reporting condition Ready=False.',
          queries.notReadyPushSecrets,
          true,
          'Go To Push Secret',
          '/d/%s/eso-resources?var-namespace=${__data.fields.Namespace}&var-push_secret_name=${__data.fields.Name}' % $._config.dashboardIds['eso-resources']
        ),

        notReadyClusterPushSecretsTable: notReadyTablePanel(
          'Not Ready Cluster Push Secrets',
          'ClusterPushSecrets currently reporting condition Ready=False.',
          queries.notReadyClusterPushSecrets,
          false,
          'Go To Push Secret',
          '/d/%s/eso-resources?var-push_secret_name=${__data.fields.Name}' % $._config.dashboardIds['eso-resources']
        ),
      };

      // Panels are grouped by concern, each with its own row: fleet-wide totals, Provider
      // integration health, then each CRD's counts/ready% (and its Cluster variant, where one
      // exists) plus what's currently not ready. Nothing here mixes panels from different
      // concerns into a shared row. Every row fills the full 24-wide grid symmetrically:
      // same-concern panels only, stat panels capped at width 6.
      local rows =
        [
          row.new('Summary') +
          row.gridPos.withX(0) +
          row.gridPos.withY(0) +
          row.gridPos.withW(24) +
          row.gridPos.withH(1),
        ] +
        grid.wrapPanels(
          [
            panels.totalResourcesCountStat,
            panels.totalReadyPercentStat,
            panels.totalNotReadyCountStat,
            panels.namespacesCountStat,
          ],
          panelWidth=6,
          panelHeight=4,
          startY=1
        ) +
        [
          row.new('Provider') +
          row.gridPos.withX(0) +
          row.gridPos.withY(5) +
          row.gridPos.withW(24) +
          row.gridPos.withH(1),
        ] +
        grid.wrapPanels(
          [
            panels.providersCountStat,
            panels.providerApiCallRateTotalStat,
            panels.providerApiErrorRateStat,
            panels.providersWithErrorsCountStat,
          ],
          panelWidth=6,
          panelHeight=4,
          startY=6
        ) +
        grid.wrapPanels(
          [
            panels.providerApiCallRateByProviderTimeSeries,
          ],
          panelWidth=24,
          panelHeight=8,
          startY=10
        ) +
        [
          row.new('External Secrets') +
          row.gridPos.withX(0) +
          row.gridPos.withY(18) +
          row.gridPos.withW(24) +
          row.gridPos.withH(1),
        ] +
        grid.wrapPanels(
          [
            panels.externalSecretsCountStat,
            panels.clusterExternalSecretsCountStat,
            panels.externalSecretsReadyPercentStat,
            panels.clusterExternalSecretReadyPercentStat,
            panels.syncCallsTotalRateStat,
            panels.syncCallsErrorRateStat,
          ],
          panelWidth=4,
          panelHeight=4,
          startY=19
        ) +
        grid.wrapPanels(
          [
            panels.externalSecretsByReadyStatusTimeSeries,
          ],
          panelWidth=24,
          panelHeight=8,
          startY=23
        ) +
        grid.wrapPanels(
          [
            panels.notReadyExternalSecretsTable,
            panels.notReadyClusterExternalSecretsTable,
          ],
          panelWidth=12,
          panelHeight=8,
          startY=31
        ) +
        [
          row.new('Secret Stores') +
          row.gridPos.withX(0) +
          row.gridPos.withY(39) +
          row.gridPos.withW(24) +
          row.gridPos.withH(1),
        ] +
        grid.wrapPanels(
          [
            panels.secretStoresCountStat,
            panels.clusterSecretStoresCountStat,
            panels.secretStoreReadyPercentStat,
            panels.clusterSecretStoreReadyPercentStat,
          ],
          panelWidth=6,
          panelHeight=4,
          startY=40
        ) +
        grid.wrapPanels(
          [
            panels.notReadySecretStoresTable,
            panels.notReadyClusterSecretStoresTable,
          ],
          panelWidth=12,
          panelHeight=8,
          startY=44
        ) +
        [
          row.new('Push Secrets') +
          row.gridPos.withX(0) +
          row.gridPos.withY(52) +
          row.gridPos.withW(24) +
          row.gridPos.withH(1),
        ] +
        grid.wrapPanels(
          [
            panels.pushSecretsCountStat,
            panels.clusterPushSecretsCountStat,
            panels.pushSecretReadyPercentStat,
            panels.clusterPushSecretReadyPercentStat,
          ],
          panelWidth=6,
          panelHeight=4,
          startY=53
        ) +
        grid.wrapPanels(
          [
            panels.notReadyPushSecretsTable,
            panels.notReadyClusterPushSecretsTable,
          ],
          panelWidth=12,
          panelHeight=8,
          startY=57
        );

      mixinUtils.dashboards.bypassDashboardValidation +
      dashboard.new(
        'External Secrets Operator / Overview',
      ) +
      dashboard.withDescription('A fleet-wide health overview for the External Secrets Operator, covering ExternalSecrets (including ClusterExternalSecrets), SecretStores (including ClusterSecretStores) and PushSecrets (including ClusterPushSecrets). Filterable by namespace and provider only - use the Resources dashboard to drill into a specific named resource. %s' % mixinUtils.dashboards.dashboardDescriptionLink('external-secrets-operator-mixin', 'https://github.com/adinhodovic/external-secrets-operator-mixin')) +
      dashboard.withUid($._config.dashboardIds[dashboardName]) +
      dashboard.withTags($._config.tags) +
      dashboard.withTimezone('utc') +
      dashboard.withEditable(false) +
      dashboard.time.withFrom('now-6h') +
      dashboard.time.withTo('now') +
      dashboard.withVariables(variables) +
      dashboard.withLinks(
        mixinUtils.dashboards.dashboardLinks('External Secrets Operator', $._config, dropdown=true)
      ) +
      dashboard.withPanels(
        rows
      ) +
      dashboard.withAnnotations(
        mixinUtils.dashboards.annotations($._config, defaultFilters)
      ),
  },
}
