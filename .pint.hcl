rule {
  match {
    name = "ExternalSecretsSyncErrors"
  }
  disable = ["promql/regexp"]
}

rule {
  match {
    name = "ExternalSecretsExternalSecretNotReady"
  }
  disable = ["promql/regexp"]
}

rule {
  match {
    name = "ExternalSecretsClusterExternalSecretNotReady"
  }
  disable = ["promql/regexp"]
}

rule {
  match {
    name = "ExternalSecretsSecretStoreNotReady"
  }
  disable = ["promql/regexp"]
}

rule {
  match {
    name = "ExternalSecretsClusterSecretStoreNotReady"
  }
  disable = ["promql/regexp"]
}

rule {
  match {
    name = "ExternalSecretsPushSecretNotReady"
  }
  disable = ["promql/regexp"]
}

rule {
  match {
    name = "ExternalSecretsClusterPushSecretNotReady"
  }
  disable = ["promql/regexp"]
}

rule {
  match {
    name = "ExternalSecretsProviderApiHighErrorRate"
  }
  disable = ["promql/regexp"]
}
