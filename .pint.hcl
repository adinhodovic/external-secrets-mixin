rule {
  match {
    name = "ExternalSecretsOperatorSyncErrors"
  }
  disable = ["promql/regexp"]
}

rule {
  match {
    name = "ExternalSecretsOperatorExternalSecretNotReady"
  }
  disable = ["promql/regexp"]
}

rule {
  match {
    name = "ExternalSecretsOperatorSecretStoreNotReady"
  }
  disable = ["promql/regexp"]
}

rule {
  match {
    name = "ExternalSecretsOperatorClusterSecretStoreNotReady"
  }
  disable = ["promql/regexp"]
}

rule {
  match {
    name = "ExternalSecretsOperatorPushSecretNotReady"
  }
  disable = ["promql/regexp"]
}

rule {
  match {
    name = "ExternalSecretsOperatorProviderApiHighErrorRate"
  }
  disable = ["promql/regexp"]
}
