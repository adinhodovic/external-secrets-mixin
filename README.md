# Prometheus Monitoring Mixin for External Secrets Operator

A set of Grafana dashboards and Prometheus alerts for the [External Secrets Operator](https://github.com/external-secrets/external-secrets) (ESO).

## How to use

This mixin is designed to be vendored into the repo with your infrastructure config. To do this, use [jsonnet-bundler](https://github.com/jsonnet-bundler/jsonnet-bundler):

You then have three options for deploying your dashboards

1. Generate the config files and deploy them yourself
2. Use jsonnet to deploy this mixin along with Prometheus and Grafana
3. Use prometheus-operator to deploy this mixin

Or import the dashboard using json in `./dashboards_out`, alternatively import them from the `Grafana.com` dashboard page.

## Generate config files

You can manually generate the alerts, dashboards and rules files, but first you must install some tools:

```sh
go get github.com/jsonnet-bundler/jsonnet-bundler/cmd/jb
brew install jsonnet
```

Then, grab the mixin and its dependencies:

```sh
git clone https://github.com/adinhodovic/external-secrets-operator-mixin
cd external-secrets-operator-mixin
jb install
```

Finally, build the mixin:

```sh
make prometheus_alerts.yaml
make dashboards_out
```

The `prometheus_alerts.yaml` file then need to passed to your Prometheus server, and the files in `dashboards_out` need to be imported into you Grafana server. The exact details will depending on how you deploy your monitoring stack.

## Metrics

This mixin relies on the metrics exposed by the External Secrets Operator itself: `externalsecret_*`, `secretstore_*`, `clustersecretstore_*`, `pushsecret_*`, `clusterpushsecret_*` and `clusterexternalsecret_*`. See the [ESO metrics documentation](https://external-secrets.io/latest/api/metrics/) for the full list. Make sure the `serviceMonitor.enabled` Helm flag (or equivalent) is set so these metrics are scraped.

For monitoring ESO's underlying controller-runtime, webhook and workqueue health, use a generic controller-runtime mixin instead - those metrics aren't specific to ESO and are shared with any kubebuilder-based operator.

## Dashboards

- **External Secrets Operator / Overview**: a focused dashboard on ExternalSecret health - sync call rates and errors, readiness, reconcile duration and provider API health.
- **External Secrets Operator / Resources**: a deep-dive into ExternalSecret, SecretStore, ClusterSecretStore, PushSecret and ClusterPushSecret readiness, sync calls, reconcile duration and provider API calls.

## Alerts

The mixin follows the [monitoring-mixins guidelines](https://github.com/monitoring-mixins/docs#guidelines-for-alert-names-labels-and-annotations) for alerts.
