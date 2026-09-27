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
local tbOverride = tbStandardOptions.override;

// Ready=True renders green, Ready=False (or absent) renders red on the bool_yes_no unit.
local readyOverride =
  tbOverride.byName.new('Ready') +
  tbOverride.byName.withPropertiesFromOptions(
    tbStandardOptions.withUnit('bool_yes_no') +
    tbStandardOptions.color.withMode('thresholds') +
    tbStandardOptions.thresholds.withSteps([
      tbStandardOptions.threshold.step.withValue(0) +
      tbStandardOptions.threshold.step.withColor('red'),
      tbStandardOptions.threshold.step.withValue(1) +
      tbStandardOptions.threshold.step.withColor('green'),
    ])
  );

{
  local dashboardName = 'eso-resources',
  grafanaDashboards+:: {
    ['%s.json' % dashboardName]:

      local defaultVariables = util.variables($._config);

      local variables = [
        defaultVariables.datasource,
        defaultVariables.cluster,
        defaultVariables.job,
        defaultVariables.namespace,
        defaultVariables.name,
        defaultVariables.provider,
        defaultVariables.secretStoreName,
        defaultVariables.pushSecretName,
      ];

      local defaultFilters = util.filters($._config);
      local namespaceLabel = defaultFilters.namespaceLabel;
      local namespaceNameLegend = '{{ %(namespaceLabel)s }}/{{ name }}' % defaultFilters;

      // Every "Overview [1h]" table below caps its rows with a topk(40, ...) set (picked by
      // readiness for most resource kinds, or by sync rate for ExternalSecret), then joins
      // the rest of that table's columns onto the same set with "and on (...)" so every
      // column lists the same 40 resources. ESO's own gauges (status_condition,
      // reconcile_duration) carry one series per replica pod - each with its own
      // container/instance/pod labels - so every aggregation below re-groups down to just the
      // resource-identifying labels (byClause) first; skipping that would let the "and on"
      // join pass pod labels through untouched and split one resource into a row per pod.
      local topAggFns = {
        readyTop40k(metricName, filterExpr, byClause):: |||
          topk(40,
            max(
              %(metricName)s{
                %(filterExpr)s,
                condition="Ready"
              }
            ) by (%(byClause)s)
          )
        ||| % { metricName: metricName, filterExpr: filterExpr, byClause: byClause },

        joinOn(byClause, innerQuery):: |||
          and on (%(byClause)s) (
            %(innerQuery)s
          )
        ||| % { byClause: byClause, innerQuery: innerQuery },

        readyStatusBy(metricName, filterExpr, byClause, joinExpr):: |||
          max(
            %(metricName)s{
              %(filterExpr)s,
              condition="Ready",
              status="True"
            }
          ) by (%(byClause)s)
          %(joinExpr)s
        ||| % { metricName: metricName, filterExpr: filterExpr, byClause: byClause, joinExpr: joinExpr },

        avgReconcileDuration1hBy(metricName, filterExpr, byClause, joinExpr):: |||
          avg(
            avg_over_time(
              %(metricName)s{
                %(filterExpr)s
              }[1h]
            )
          ) by (%(byClause)s)
          %(joinExpr)s
        ||| % { metricName: metricName, filterExpr: filterExpr, byClause: byClause, joinExpr: joinExpr },

        reconcileDurationSumBy(metricName, filterExpr, byClause):: |||
          sum(
            %(metricName)s{
              %(filterExpr)s
            }
          ) by (%(byClause)s)
        ||| % { metricName: metricName, filterExpr: filterExpr, byClause: byClause },

        sumRate1hBy(metricName, filterExpr, byClause, joinExpr):: |||
          sum(
            rate(
              %(metricName)s{
                %(filterExpr)s
              }[1h]
            )
          ) by (%(byClause)s)
          %(joinExpr)s
        ||| % { metricName: metricName, filterExpr: filterExpr, byClause: byClause, joinExpr: joinExpr },

        top20(innerQuery):: |||
          topk(20,
            %(innerQuery)s
          )
        ||| % { innerQuery: innerQuery },
      };

      // "<namespaceLabel>, name" and "name" are already-resolved strings (no more %(...)s
      // placeholders left in them), so passing them into topAggFns' own %-formatting below is
      // a single, safe substitution pass - not a second round of templating.
      local namespacedBy = '%s, name' % namespaceLabel;
      local clusterBy = 'name';

      local queries = {
        // External Secret
        syncCallsTotalRate: |||
          sum(
            rate(
              externalsecret_sync_calls_total{
                %(externalSecret)s
              }[$__rate_interval]
            )
          )
        ||| % defaultFilters,

        syncCallsErrorRate: |||
          sum(
            rate(
              externalsecret_sync_calls_error{
                %(externalSecret)s
              }[$__rate_interval]
            )
          )
        ||| % defaultFilters,

        syncCallsByNamespaceName1h: |||
          topk(20,
            sum(
              rate(
                externalsecret_sync_calls_total{
                  %(externalSecret)s
                }[1h]
              )
            ) by (%(namespaceLabel)s, name)
          )
        ||| % defaultFilters,

        syncErrorsByNamespaceName1h: |||
          topk(20,
            sum(
              rate(
                externalsecret_sync_calls_error{
                  %(externalSecret)s
                }[1h]
              )
            ) by (%(namespaceLabel)s, name)
          )
        ||| % defaultFilters,

        reconcileDurationByNamespaceName: topAggFns.top20(
          topAggFns.reconcileDurationSumBy('externalsecret_reconcile_duration', defaultFilters.externalSecret, namespacedBy)
        ),

        providerApiCallRateByProviderCall: topAggFns.top20(|||
          sum(
            rate(
              externalsecret_provider_api_calls_count{
                %(providerRuntime)s
              }[$__rate_interval]
            )
          ) by (provider, call)
        ||| % defaultFilters),

        providerApiCallErrorRateByProviderCall: topAggFns.top20(|||
          sum(
            rate(
              externalsecret_provider_api_calls_count{
                %(providerRuntime)s,
                status="error"
              }[$__rate_interval]
            )
          ) by (provider, call)
        ||| % defaultFilters),

        externalSecretRateTop40k: |||
          topk(40,
            sum(
              rate(
                externalsecret_sync_calls_total{
                  %(externalSecret)s
                }[1h]
              )
            ) by (%(namespaceLabel)s, name)
          )
        ||| % defaultFilters,
        local externalSecretJoin = topAggFns.joinOn(namespacedBy, queries.externalSecretRateTop40k),

        externalSecretErrorRate1hByNamespaceName: topAggFns.sumRate1hBy(
          'externalsecret_sync_calls_error', defaultFilters.externalSecret, namespacedBy, externalSecretJoin
        ),

        externalSecretReconcileDuration1hByNamespaceName: topAggFns.avgReconcileDuration1hBy(
          'externalsecret_reconcile_duration', defaultFilters.externalSecret, namespacedBy, externalSecretJoin
        ),

        externalSecretReadyByNamespaceName: topAggFns.readyStatusBy(
          'externalsecret_status_condition', defaultFilters.externalSecret, namespacedBy, externalSecretJoin
        ),

        // Cluster External Secret
        clusterExternalSecretReadyTop40k: topAggFns.readyTop40k(
          'clusterexternalsecret_status_condition', defaultFilters.default, clusterBy
        ),
        local clusterExternalSecretJoin = topAggFns.joinOn(clusterBy, queries.clusterExternalSecretReadyTop40k),

        clusterExternalSecretReadyStatusByName: topAggFns.readyStatusBy(
          'clusterexternalsecret_status_condition', defaultFilters.default, clusterBy, clusterExternalSecretJoin
        ),

        clusterExternalSecretReconcileDuration1hByName: topAggFns.avgReconcileDuration1hBy(
          'clusterexternalsecret_reconcile_duration', defaultFilters.default, clusterBy, clusterExternalSecretJoin
        ),

        clusterExternalSecretReconcileDurationByName: topAggFns.top20(
          topAggFns.reconcileDurationSumBy('clusterexternalsecret_reconcile_duration', defaultFilters.default, clusterBy)
        ),

        // Secret Store
        secretStoreReconcileDurationByNamespaceName: topAggFns.top20(
          topAggFns.reconcileDurationSumBy('secretstore_reconcile_duration', defaultFilters.secretStore, namespacedBy)
        ),

        clusterSecretStoreReconcileDurationByName: topAggFns.top20(
          topAggFns.reconcileDurationSumBy('clustersecretstore_reconcile_duration', defaultFilters.default, clusterBy)
        ),

        secretStoreReadyTop40k: topAggFns.readyTop40k(
          'secretstore_status_condition', defaultFilters.secretStore, namespacedBy
        ),
        local secretStoreJoin = topAggFns.joinOn(namespacedBy, queries.secretStoreReadyTop40k),

        secretStoreReadyStatusByNamespaceName: topAggFns.readyStatusBy(
          'secretstore_status_condition', defaultFilters.secretStore, namespacedBy, secretStoreJoin
        ),

        secretStoreReconcileDuration1hByNamespaceName: topAggFns.avgReconcileDuration1hBy(
          'secretstore_reconcile_duration', defaultFilters.secretStore, namespacedBy, secretStoreJoin
        ),

        clusterSecretStoreReadyTop40k: topAggFns.readyTop40k(
          'clustersecretstore_status_condition', defaultFilters.default, clusterBy
        ),
        local clusterSecretStoreJoin = topAggFns.joinOn(clusterBy, queries.clusterSecretStoreReadyTop40k),

        clusterSecretStoreReadyStatusByName: topAggFns.readyStatusBy(
          'clustersecretstore_status_condition', defaultFilters.default, clusterBy, clusterSecretStoreJoin
        ),

        clusterSecretStoreReconcileDuration1hByName: topAggFns.avgReconcileDuration1hBy(
          'clustersecretstore_reconcile_duration', defaultFilters.default, clusterBy, clusterSecretStoreJoin
        ),

        // Push Secret
        pushSecretReconcileDurationByNamespaceName: topAggFns.top20(
          topAggFns.reconcileDurationSumBy('pushsecret_reconcile_duration', defaultFilters.pushSecret, namespacedBy)
        ),

        clusterPushSecretReconcileDurationByName: topAggFns.top20(
          topAggFns.reconcileDurationSumBy('clusterpushsecret_reconcile_duration', defaultFilters.default, clusterBy)
        ),

        pushSecretReadyTop40k: topAggFns.readyTop40k(
          'pushsecret_status_condition', defaultFilters.pushSecret, namespacedBy
        ),
        local pushSecretJoin = topAggFns.joinOn(namespacedBy, queries.pushSecretReadyTop40k),

        pushSecretReadyStatusByNamespaceName: topAggFns.readyStatusBy(
          'pushsecret_status_condition', defaultFilters.pushSecret, namespacedBy, pushSecretJoin
        ),

        pushSecretReconcileDuration1hByNamespaceName: topAggFns.avgReconcileDuration1hBy(
          'pushsecret_reconcile_duration', defaultFilters.pushSecret, namespacedBy, pushSecretJoin
        ),

        clusterPushSecretReadyTop40k: topAggFns.readyTop40k(
          'clusterpushsecret_status_condition', defaultFilters.default, clusterBy
        ),
        local clusterPushSecretJoin = topAggFns.joinOn(clusterBy, queries.clusterPushSecretReadyTop40k),

        clusterPushSecretReadyStatusByName: topAggFns.readyStatusBy(
          'clusterpushsecret_status_condition', defaultFilters.default, clusterBy, clusterPushSecretJoin
        ),

        clusterPushSecretReconcileDuration1hByName: topAggFns.avgReconcileDuration1hBy(
          'clusterpushsecret_reconcile_duration', defaultFilters.default, clusterBy, clusterPushSecretJoin
        ),
      };

      local panels = {

        // External Secret
        syncCallsByNamespaceNamePieChart:
          mixinUtils.dashboards.pieChartPanel(
            'Sync Calls by External Secret [1h, Top 20]',
            'reqps',
            queries.syncCallsByNamespaceName1h,
            namespaceNameLegend,
            description='Distribution of sync call volume across ExternalSecrets over the past hour. Identifies which secrets are synced the most frequently.',
          ),

        syncErrorsByNamespaceNamePieChart:
          mixinUtils.dashboards.pieChartPanel(
            'Sync Errors by External Secret [1h, Top 20]',
            'reqps',
            queries.syncErrorsByNamespaceName1h,
            namespaceNameLegend,
            description='Distribution of sync errors across ExternalSecrets over the past hour. A concentration of errors on a single secret usually points to a specific misconfiguration, while broad errors point to a provider-wide issue.',
          ),

        syncCallsTimeSeries:
          mixinUtils.dashboards.timeSeriesPanel(
            'Sync Calls',
            'reqps',
            [
              {
                expr: queries.syncCallsTotalRate,
                legend: 'Total',
              },
              {
                expr: queries.syncCallsErrorRate,
                legend: 'Errors',
              },
            ],
            description='Rate of ExternalSecret sync attempts versus failed sync attempts over time for the selected filters.',
          ),

        reconcileDurationTimeSeries:
          mixinUtils.dashboards.timeSeriesPanel(
            'Reconcile Duration by External Secret [Top 20]',
            'ns',
            queries.reconcileDurationByNamespaceName,
            namespaceNameLegend,
            description='Last reported reconcile duration per ExternalSecret. Rising durations indicate slower provider responses or larger secret payloads.',
            stack='normal',
          ),

        providerApiCallRateTimeSeries:
          mixinUtils.dashboards.timeSeriesPanel(
            'Provider API Call Rate by Call [Top 20]',
            'reqps',
            queries.providerApiCallRateByProviderCall,
            '{{ provider }} - {{ call }}',
            description='Rate of API calls made to the upstream provider, broken down by provider and API call type (e.g. GetSecret, PushSecret).',
            stack='normal',
          ),

        providerApiCallErrorRateTimeSeries:
          mixinUtils.dashboards.timeSeriesPanel(
            'Provider API Call Error Rate by Call [Top 20]',
            'reqps',
            queries.providerApiCallErrorRateByProviderCall,
            '{{ provider }} - {{ call }}',
            description='Rate of failed API calls made to the upstream provider, broken down by provider and API call type.',
            stack='normal',
          ),

        externalSecretTable:
          mixinUtils.dashboards.tablePanel(
            'External Secret Overview [1h]',
            'short',
            [
              {
                expr: queries.externalSecretRateTop40k,
                legend: 'Sync Rate',
              },
              {
                expr: queries.externalSecretErrorRate1hByNamespaceName,
                legend: 'Sync Error Rate',
              },
              {
                expr: queries.externalSecretReconcileDuration1hByNamespaceName,
                legend: 'Reconcile Duration',
              },
              {
                expr: queries.externalSecretReadyByNamespaceName,
                legend: 'Ready',
              },
            ],
            description='An overview table showing various metrics by ExternalSecret [1h].',
            sortBy={ name: 'Sync Rate', desc: true },
            transformations=[
              tbQueryOptions.transformation.withId('merge'),
              tbQueryOptions.transformation.withId('organize') +
              tbQueryOptions.transformation.withOptions({
                renameByName: {
                  [namespaceLabel]: 'Namespace',
                  name: 'Name',
                  'Value #A': 'Sync Rate',
                  'Value #B': 'Sync Error Rate',
                  'Value #C': 'Reconcile Duration',
                  'Value #D': 'Ready',
                },
                indexByName: {
                  [namespaceLabel]: 0,
                  name: 1,
                  'Value #A': 2,
                  'Value #B': 3,
                  'Value #C': 4,
                  'Value #D': 5,
                },
                excludeByName: {
                  Time: true,
                },
              }),
            ],
            overrides=[
              tbOverride.byName.new('Sync Rate') +
              tbOverride.byName.withPropertiesFromOptions(
                tbStandardOptions.withUnit('reqps')
              ),
              tbOverride.byName.new('Sync Error Rate') +
              tbOverride.byName.withPropertiesFromOptions(
                tbStandardOptions.withUnit('reqps')
              ),
              tbOverride.byName.new('Reconcile Duration') +
              tbOverride.byName.withPropertiesFromOptions(
                tbStandardOptions.withUnit('ns')
              ),
              readyOverride,
            ],
          ),

        clusterExternalSecretReconcileDurationTimeSeries:
          mixinUtils.dashboards.timeSeriesPanel(
            'Cluster External Secret Reconcile Duration [Top 20]',
            'ns',
            queries.clusterExternalSecretReconcileDurationByName,
            '{{ name }}',
            description='Last reported reconcile duration per ClusterExternalSecret.',
            stack='normal',
          ),

        clusterExternalSecretTable:
          mixinUtils.dashboards.tablePanel(
            'Cluster External Secret Overview [1h]',
            'short',
            [
              {
                expr: queries.clusterExternalSecretReadyStatusByName,
                legend: 'Ready',
              },
              {
                expr: queries.clusterExternalSecretReconcileDuration1hByName,
                legend: 'Reconcile Duration',
              },
            ],
            description='An overview table showing readiness and reconcile duration by ClusterExternalSecret [1h].',
            sortBy={ name: 'Ready', desc: false },
            transformations=[
              tbQueryOptions.transformation.withId('merge'),
              tbQueryOptions.transformation.withId('organize') +
              tbQueryOptions.transformation.withOptions({
                renameByName: {
                  name: 'Name',
                  'Value #A': 'Ready',
                  'Value #B': 'Reconcile Duration',
                },
                excludeByName: {
                  Time: true,
                },
              }),
            ],
            overrides=[
              readyOverride,
              tbOverride.byName.new('Reconcile Duration') +
              tbOverride.byName.withPropertiesFromOptions(
                tbStandardOptions.withUnit('ns')
              ),
            ],
          ),

        // Secret Store
        secretStoreReconcileDurationTimeSeries:
          mixinUtils.dashboards.timeSeriesPanel(
            'Secret Store Reconcile Duration [Top 20]',
            'ns',
            queries.secretStoreReconcileDurationByNamespaceName,
            namespaceNameLegend,
            description='Last reported reconcile duration per SecretStore.',
            stack='normal',
          ),

        clusterSecretStoreReconcileDurationTimeSeries:
          mixinUtils.dashboards.timeSeriesPanel(
            'Cluster Secret Store Reconcile Duration [Top 20]',
            'ns',
            queries.clusterSecretStoreReconcileDurationByName,
            '{{ name }}',
            description='Last reported reconcile duration per ClusterSecretStore.',
            stack='normal',
          ),

        secretStoreTable:
          mixinUtils.dashboards.tablePanel(
            'Secret Store Overview [1h]',
            'short',
            [
              {
                expr: queries.secretStoreReadyStatusByNamespaceName,
                legend: 'Ready',
              },
              {
                expr: queries.secretStoreReconcileDuration1hByNamespaceName,
                legend: 'Reconcile Duration',
              },
            ],
            description='An overview table showing readiness and reconcile duration by SecretStore [1h].',
            sortBy={ name: 'Ready', desc: false },
            transformations=[
              tbQueryOptions.transformation.withId('merge'),
              tbQueryOptions.transformation.withId('organize') +
              tbQueryOptions.transformation.withOptions({
                renameByName: {
                  [namespaceLabel]: 'Namespace',
                  name: 'Name',
                  'Value #A': 'Ready',
                  'Value #B': 'Reconcile Duration',
                },
                excludeByName: {
                  Time: true,
                },
              }),
            ],
            overrides=[
              readyOverride,
              tbOverride.byName.new('Reconcile Duration') +
              tbOverride.byName.withPropertiesFromOptions(
                tbStandardOptions.withUnit('ns')
              ),
            ],
          ),

        clusterSecretStoreTable:
          mixinUtils.dashboards.tablePanel(
            'Cluster Secret Store Overview [1h]',
            'short',
            [
              {
                expr: queries.clusterSecretStoreReadyStatusByName,
                legend: 'Ready',
              },
              {
                expr: queries.clusterSecretStoreReconcileDuration1hByName,
                legend: 'Reconcile Duration',
              },
            ],
            description='An overview table showing readiness and reconcile duration by ClusterSecretStore [1h].',
            sortBy={ name: 'Ready', desc: false },
            transformations=[
              tbQueryOptions.transformation.withId('merge'),
              tbQueryOptions.transformation.withId('organize') +
              tbQueryOptions.transformation.withOptions({
                renameByName: {
                  name: 'Name',
                  'Value #A': 'Ready',
                  'Value #B': 'Reconcile Duration',
                },
                excludeByName: {
                  Time: true,
                },
              }),
            ],
            overrides=[
              readyOverride,
              tbOverride.byName.new('Reconcile Duration') +
              tbOverride.byName.withPropertiesFromOptions(
                tbStandardOptions.withUnit('ns')
              ),
            ],
          ),

        // Push Secret
        pushSecretReconcileDurationTimeSeries:
          mixinUtils.dashboards.timeSeriesPanel(
            'Push Secret Reconcile Duration [Top 20]',
            'ns',
            queries.pushSecretReconcileDurationByNamespaceName,
            namespaceNameLegend,
            description='Last reported reconcile duration per PushSecret.',
            stack='normal',
          ),

        clusterPushSecretReconcileDurationTimeSeries:
          mixinUtils.dashboards.timeSeriesPanel(
            'Cluster Push Secret Reconcile Duration [Top 20]',
            'ns',
            queries.clusterPushSecretReconcileDurationByName,
            '{{ name }}',
            description='Last reported reconcile duration per ClusterPushSecret.',
            stack='normal',
          ),

        pushSecretTable:
          mixinUtils.dashboards.tablePanel(
            'Push Secret Overview [1h]',
            'short',
            [
              {
                expr: queries.pushSecretReadyStatusByNamespaceName,
                legend: 'Ready',
              },
              {
                expr: queries.pushSecretReconcileDuration1hByNamespaceName,
                legend: 'Reconcile Duration',
              },
            ],
            description='An overview table showing readiness and reconcile duration by PushSecret [1h].',
            sortBy={ name: 'Ready', desc: false },
            transformations=[
              tbQueryOptions.transformation.withId('merge'),
              tbQueryOptions.transformation.withId('organize') +
              tbQueryOptions.transformation.withOptions({
                renameByName: {
                  [namespaceLabel]: 'Namespace',
                  name: 'Name',
                  'Value #A': 'Ready',
                  'Value #B': 'Reconcile Duration',
                },
                excludeByName: {
                  Time: true,
                },
              }),
            ],
            overrides=[
              readyOverride,
              tbOverride.byName.new('Reconcile Duration') +
              tbOverride.byName.withPropertiesFromOptions(
                tbStandardOptions.withUnit('ns')
              ),
            ],
          ),

        clusterPushSecretTable:
          mixinUtils.dashboards.tablePanel(
            'Cluster Push Secret Overview [1h]',
            'short',
            [
              {
                expr: queries.clusterPushSecretReadyStatusByName,
                legend: 'Ready',
              },
              {
                expr: queries.clusterPushSecretReconcileDuration1hByName,
                legend: 'Reconcile Duration',
              },
            ],
            description='An overview table showing readiness and reconcile duration by ClusterPushSecret [1h].',
            sortBy={ name: 'Ready', desc: false },
            transformations=[
              tbQueryOptions.transformation.withId('merge'),
              tbQueryOptions.transformation.withId('organize') +
              tbQueryOptions.transformation.withOptions({
                renameByName: {
                  name: 'Name',
                  'Value #A': 'Ready',
                  'Value #B': 'Reconcile Duration',
                },
                excludeByName: {
                  Time: true,
                },
              }),
            ],
            overrides=[
              readyOverride,
              tbOverride.byName.new('Reconcile Duration') +
              tbOverride.byName.withPropertiesFromOptions(
                tbStandardOptions.withUnit('ns')
              ),
            ],
          ),
      };

      // Rows for the less-frequently-needed CRD kinds (everything past ExternalSecret) start
      // collapsed so the dashboard opens on the Provider and External Secret content only;
      // their panels are nested under the row via withPanels rather than laid out as
      // top-level, so collapsing them doesn't leave a vertical gap. panelGroups is a list of
      // {panels, width, height} stacked top to bottom starting at y + 1.
      local collapsedRow(title, y, panelGroups) =
        local step(acc, group) = {
          out: acc.out + grid.wrapPanels(group.panels, group.width, group.height, startY=acc.y),
          y: acc.y + group.height,
        };
        local nestedPanels = std.foldl(step, panelGroups, { out: [], y: y + 1 }).out;
        row.new(title) +
        row.gridPos.withX(0) +
        row.gridPos.withY(y) +
        row.gridPos.withW(24) +
        row.gridPos.withH(1) +
        row.withCollapsed(true) +
        row.withPanels(nestedPanels);

      // No fleet-wide summary stats here - those live on the Overview dashboard. Every row
      // below is breakdown content for one CRD: per-resource pies/time series (top 20/40 by
      // name to keep the graph readable) and a per-resource overview table.
      local rows =
        [
          row.new('Provider') +
          row.gridPos.withX(0) +
          row.gridPos.withY(0) +
          row.gridPos.withW(24) +
          row.gridPos.withH(1),
        ] +
        grid.wrapPanels(
          [
            panels.providerApiCallRateTimeSeries,
            panels.providerApiCallErrorRateTimeSeries,
          ],
          panelWidth=12,
          panelHeight=8,
          startY=1
        ) +
        [
          row.new('External Secret') +
          row.gridPos.withX(0) +
          row.gridPos.withY(9) +
          row.gridPos.withW(24) +
          row.gridPos.withH(1),
        ] +
        grid.wrapPanels(
          [
            panels.syncCallsByNamespaceNamePieChart,
            panels.syncErrorsByNamespaceNamePieChart,
          ],
          panelWidth=12,
          panelHeight=6,
          startY=10
        ) +
        grid.wrapPanels(
          [
            panels.syncCallsTimeSeries,
            panels.reconcileDurationTimeSeries,
          ],
          panelWidth=12,
          panelHeight=8,
          startY=16
        ) +
        grid.wrapPanels(
          [
            panels.externalSecretTable,
          ],
          panelWidth=24,
          panelHeight=12,
          startY=24
        ) +
        [
          collapsedRow('Cluster External Secret', 36, [
            { panels: [panels.clusterExternalSecretReconcileDurationTimeSeries], width: 24, height: 8 },
            { panels: [panels.clusterExternalSecretTable], width: 24, height: 10 },
          ]),
          collapsedRow('Secret Store', 37, [
            { panels: [panels.secretStoreReconcileDurationTimeSeries], width: 24, height: 8 },
            { panels: [panels.secretStoreTable], width: 24, height: 10 },
          ]),
          collapsedRow('Cluster Secret Store', 38, [
            { panels: [panels.clusterSecretStoreReconcileDurationTimeSeries], width: 24, height: 8 },
            { panels: [panels.clusterSecretStoreTable], width: 24, height: 10 },
          ]),
          collapsedRow('Push Secret', 39, [
            { panels: [panels.pushSecretReconcileDurationTimeSeries], width: 24, height: 8 },
            { panels: [panels.pushSecretTable], width: 24, height: 10 },
          ]),
          collapsedRow('Cluster Push Secret', 40, [
            { panels: [panels.clusterPushSecretReconcileDurationTimeSeries], width: 24, height: 8 },
            { panels: [panels.clusterPushSecretTable], width: 24, height: 10 },
          ]),
        ];

      mixinUtils.dashboards.bypassDashboardValidation +
      dashboard.new(
        'External Secrets Operator / Resources',
      ) +
      dashboard.withDescription('A deep-dive, per-resource breakdown dashboard for the resources managed by the External Secrets Operator: ExternalSecret, ClusterExternalSecret, SecretStore, ClusterSecretStore, PushSecret and ClusterPushSecret. Shows sync call rates and errors, reconcile duration, readiness and provider API call health broken down per resource - see the Overview dashboard for fleet-wide totals. %s' % mixinUtils.dashboards.dashboardDescriptionLink('external-secrets-operator-mixin', 'https://github.com/adinhodovic/external-secrets-operator-mixin')) +
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
