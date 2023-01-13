variable "kubernetes-context" {
  default = "docker-desktop"
}

terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "2.8.0"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "1.14.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "2.2.3"
    }
    minio = {
      source  = "aminueza/minio"
      version = "1.10.0"
    }
  }
}

provider "helm" {
  kubernetes {
    config_context = var.kubernetes-context
    config_path    = "~/.kube/config"
  }
}

provider "kubectl" {
  config_context = var.kubernetes-context
  config_path    = "~/.kube/config"
}

resource "helm_release" "nginx_ingress" {
  name       = "nginx-ingress-controller"
  namespace  = "default"
  repository = "https://charts.bitnami.com/bitnami"
  chart      = "nginx-ingress-controller"

  set {
    name  = "service.type"
    value = "LoadBalancer"
  }

  wait = true
}

data "kubectl_file_documents" "minio_docs" {
  content = file("k8s/minio.yaml")
}

resource "kubectl_manifest" "minio" {
  for_each  = data.kubectl_file_documents.minio_docs.manifests
  yaml_body = each.value
}


provider minio {
  minio_server   = "minio-api.localhost"
  minio_user     = "minioadmin"
  minio_password = "minioadmin"

  minio_insecure = true
}

resource "minio_s3_bucket" "loki" {
  bucket = "loki"
  acl    = "public"
}


resource "minio_s3_bucket" "tempo" {
  bucket = "tempo"
  acl    = "public"
}

resource "helm_release" "metrics_server" {
  chart      = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  name       = "metrics-server"
  wait       = true
  version    = "3.8.3"
  values     = [
    file("${path.module}/helm/metrics_server.values.yaml")
  ]
}

### https://www.atatus.com/blog/a-beginners-guide-for-grafana-loki/
resource "helm_release" "loki_distributed" {
  chart      = "loki-distributed"
  repository = "https://grafana.github.io/helm-charts"
  name       = "loki-distributed"

  wait    = true
  version = "0.67.1"

  namespace = "monitoring"

  create_namespace = true

  depends_on = [
    helm_release.metrics_server,
    minio_s3_bucket.loki,
    minio_s3_bucket.tempo
  ]

  values = [
    file("${path.module}/helm/loki.values.yaml")
  ]
}

## https://anaisurl.com/full-tutorial-monitoring/
resource "helm_release" "promtail" {
  chart      = "promtail"
  repository = "https://grafana.github.io/helm-charts"
  name       = "promtail"

  wait    = true
  version = "6.7.4"

  namespace = "monitoring"

  create_namespace = true

  depends_on = [helm_release.loki_distributed]

  values = [
    file("${path.module}/helm/promtail.values.yaml")
  ]
}

resource "helm_release" "tempo" {
  chart      = "tempo-distributed"
  repository = "https://grafana.github.io/helm-charts"
  name       = "tempo-distributed"

  wait    = true
  version = "0.27.10"

  namespace = "monitoring"

  create_namespace = true


  values = [
    file("${path.module}/helm/tempo_distributed.values.yaml")
  ]
}

resource "helm_release" "opentelemetry_collector" {
  chart      = "opentelemetry-collector"
  repository = "https://open-telemetry.github.io/opentelemetry-helm-charts"
  name       = "opentelemetry-collector"

  wait    = true
  version = "0.43.2"

  namespace = "monitoring"

  create_namespace = true

  values = [
    file("${path.module}/helm/opentelemetry_collector.values.yaml")
  ]
}


resource "helm_release" "kube_prometheus_stack" {
  chart      = "kube-prometheus-stack"
  repository = "https://prometheus-community.github.io/helm-charts"
  name       = "kube-prometheus-stack"

  wait    = true
  version = "43.1.3"

  namespace = "monitoring"

  create_namespace = true

  depends_on = [helm_release.loki_distributed]

  values = [
    file("${path.module}/helm/kube_prometheus_stack.values.yaml")
  ]
}
