local g = import 'github.com/grafana/grafonnet/gen/grafonnet-latest/main.libsonnet';

local dashboard = g.dashboard;

local variable = dashboard.variable;
local datasource = variable.datasource;
local query = variable.query;

{
  filters(config):: {
    local this = self,
    cluster: '%(clusterLabel)s="$cluster"' % config,
    job: 'job=~"$job"',
    provider: 'provider=~"$provider"',
    // Exposed so dashboard queries can group/legend/table-key off the same configurable
    // label (see config.libsonnet's namespaceLabel comment for why this isn't just "namespace").
    namespaceLabel: config.namespaceLabel,
    namespace: '%(namespaceLabel)s=~"$namespace"' % config,
    name: 'name=~"$name"',
    // Literal match for single selection
    nameSingle: 'name="$name"',
    secretStoreNamespace: '%(namespaceLabel)s=~"$secret_store_namespace"' % config,
    secretStoreName: 'name=~"$secret_store_name"',
    secretStoreNameSingle: 'name="$secret_store_name"',
    pushSecretNamespace: '%(namespaceLabel)s=~"$push_secret_namespace"' % config,
    pushSecretName: 'name=~"$push_secret_name"',
    pushSecretNameSingle: 'name="$push_secret_name"',

    base: |||
      %(cluster)s,
      %(job)s
    ||| % this,

    default: |||
      %(base)s
    ||| % this,

    providerRuntime: |||
      %(base)s,
      %(provider)s
    ||| % this,

    // Namespace-only, no resource name - for overview-level queries spanning all of ESO's
    // namespaced resource kinds (ExternalSecret, SecretStore, PushSecret) at once.
    namespaced: |||
      %(base)s,
      %(namespace)s
    ||| % this,

    externalSecret: |||
      %(base)s,
      %(namespace)s,
      %(name)s
    ||| % this,

    externalSecretSingle: |||
      %(base)s,
      %(namespace)s,
      %(nameSingle)s
    ||| % this,

    secretStore: |||
      %(base)s,
      %(secretStoreNamespace)s,
      %(secretStoreName)s
    ||| % this,

    secretStoreSingle: |||
      %(base)s,
      %(secretStoreNamespace)s,
      %(secretStoreNameSingle)s
    ||| % this,

    pushSecret: |||
      %(base)s,
      %(pushSecretNamespace)s,
      %(pushSecretName)s
    ||| % this,

    pushSecretSingle: |||
      %(base)s,
      %(pushSecretNamespace)s,
      %(pushSecretNameSingle)s
    ||| % this,
  },

  variables(config):: {
    local this = self,

    local defaultFilters = $.filters(config),

    datasource:
      datasource.new(
        'datasource',
        'prometheus',
      ) +
      datasource.generalOptions.withLabel('Data source') +
      {
        current: {
          selected: true,
          text: config.datasourceName,
          value: config.datasourceName,
        },
      },

    cluster:
      query.new(
        'cluster',
        'label_values(externalsecret_status_condition{}, %(clusterLabel)s)' % config,
      ) +
      query.withDatasourceFromVariable(this.datasource) +
      query.withSort() +
      query.generalOptions.withLabel('Cluster') +
      query.refresh.onLoad() +
      query.refresh.onTime() +
      (
        if config.showMultiCluster
        then query.generalOptions.showOnDashboard.withLabelAndValue()
        else query.generalOptions.showOnDashboard.withNothing()
      ),

    job:
      query.new(
        'job',
        'label_values(externalsecret_status_condition{%(cluster)s}, job)' % defaultFilters
      ) +
      query.withDatasourceFromVariable(this.datasource) +
      query.withSort() +
      query.generalOptions.withLabel('Job') +
      query.selectionOptions.withMulti(true) +
      query.selectionOptions.withIncludeAll(true) +
      query.refresh.onLoad() +
      query.refresh.onTime(),

    provider:
      query.new(
        'provider',
        'label_values(externalsecret_provider_api_calls_count{%(cluster)s, %(job)s}, provider)' % defaultFilters
      ) +
      query.withDatasourceFromVariable(this.datasource) +
      query.withSort() +
      query.generalOptions.withLabel('Provider') +
      query.selectionOptions.withMulti(true) +
      query.selectionOptions.withIncludeAll(true) +
      query.refresh.onLoad() +
      query.refresh.onTime(),

    namespace:
      query.new(
        'namespace',
        'label_values(externalsecret_status_condition{%(cluster)s, %(job)s}, %(namespaceLabel)s)' % defaultFilters
      ) +
      query.withDatasourceFromVariable(this.datasource) +
      query.withSort() +
      query.generalOptions.withLabel('Namespace') +
      query.selectionOptions.withMulti(true) +
      query.selectionOptions.withIncludeAll(true) +
      query.refresh.onLoad() +
      query.refresh.onTime(),

    name:
      query.new(
        'name',
        'label_values(externalsecret_status_condition{%(cluster)s, %(job)s, %(namespace)s}, name)' % defaultFilters
      ) +
      query.withDatasourceFromVariable(this.datasource) +
      query.withSort() +
      query.generalOptions.withLabel('External Secret') +
      query.selectionOptions.withMulti(true) +
      query.selectionOptions.withIncludeAll(true) +
      query.refresh.onLoad() +
      query.refresh.onTime(),

    nameSingle:
      this.name +
      query.selectionOptions.withMulti(false) +
      query.selectionOptions.withIncludeAll(false),

    secretStoreNamespace:
      query.new(
        'secret_store_namespace',
        'label_values(secretstore_status_condition{%(cluster)s, %(job)s}, %(namespaceLabel)s)' % defaultFilters
      ) +
      query.withDatasourceFromVariable(this.datasource) +
      query.withSort() +
      query.generalOptions.withLabel('Namespace') +
      query.selectionOptions.withMulti(true) +
      query.selectionOptions.withIncludeAll(true) +
      query.refresh.onLoad() +
      query.refresh.onTime(),

    secretStoreName:
      query.new(
        'secret_store_name',
        'label_values(secretstore_status_condition{%(cluster)s, %(job)s, %(secretStoreNamespace)s}, name)' % defaultFilters
      ) +
      query.withDatasourceFromVariable(this.datasource) +
      query.withSort() +
      query.generalOptions.withLabel('Secret Store') +
      query.selectionOptions.withMulti(true) +
      query.selectionOptions.withIncludeAll(true) +
      query.refresh.onLoad() +
      query.refresh.onTime(),

    secretStoreNameSingle:
      this.secretStoreName +
      query.selectionOptions.withMulti(false) +
      query.selectionOptions.withIncludeAll(false),

    pushSecretNamespace:
      query.new(
        'push_secret_namespace',
        'label_values(pushsecret_status_condition{%(cluster)s, %(job)s}, %(namespaceLabel)s)' % defaultFilters
      ) +
      query.withDatasourceFromVariable(this.datasource) +
      query.withSort() +
      query.generalOptions.withLabel('Namespace') +
      query.selectionOptions.withMulti(true) +
      query.selectionOptions.withIncludeAll(true) +
      query.refresh.onLoad() +
      query.refresh.onTime(),

    pushSecretName:
      query.new(
        'push_secret_name',
        'label_values(pushsecret_status_condition{%(cluster)s, %(job)s, %(pushSecretNamespace)s}, name)' % defaultFilters
      ) +
      query.withDatasourceFromVariable(this.datasource) +
      query.withSort() +
      query.generalOptions.withLabel('Push Secret') +
      query.selectionOptions.withMulti(true) +
      query.selectionOptions.withIncludeAll(true) +
      query.refresh.onLoad() +
      query.refresh.onTime(),

    pushSecretNameSingle:
      this.pushSecretName +
      query.selectionOptions.withMulti(false) +
      query.selectionOptions.withIncludeAll(false),
  },
}
