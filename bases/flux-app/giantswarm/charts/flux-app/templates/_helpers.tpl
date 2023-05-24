{{/* vim: set filetype=mustache: */}}
{{/*
Expand the name of the chart.
*/}}
{{- define "name" -}}
{{- .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Common labels
*/}}
{{- define "labels.common" -}}
{{ include "labels.selector" . }}
app.kubernetes.io/managed-by: {{ .Release.Service | quote }}
application.giantswarm.io/team: {{ index .Chart.Annotations "application.giantswarm.io/team" | quote }}
helm.sh/chart: {{ include "chart" . | quote }}
{{- end -}}

{{/*
Selector labels
*/}}
{{- define "labels.selector" -}}
app.kubernetes.io/name: {{ include "name" . | quote }}
app.kubernetes.io/instance: {{ .Release.Name | quote }}
{{- end -}}

{{- define "crdInstall" -}}
{{- printf "%s-%s" ( include "name" . ) "crd-install" | replace "+" "_" | trimSuffix "-" -}}
{{- end -}}

{{- define "crdInstallJob" -}}
{{- printf "%s-%s-%s" ( include "name" . ) "crd-install" .Chart.AppVersion | replace "+" "_" | replace "." "-" | trimSuffix "-" | trunc 63 -}}
{{- end -}}

{{- define "crdInstallAnnotations" -}}
"helm.sh/hook": "pre-install,pre-upgrade"
"helm.sh/hook-delete-policy": "before-hook-creation,hook-succeeded,hook-failed"
{{- end -}}

{{/* Create a label which can be used to select any orphaned crd-install hook resources */}}
{{- define "crdInstallSelector" -}}
{{- printf "%s" "crd-install-hook" -}}
{{- end -}}

{{/* Usage:
    {{ include "controllerVolumeName" (merge (dict "volumeName" "hello") .) | quote }}
*/}}
{{- define "controllerVolumeName" -}}
{{- printf "%s-controller-%s-volume" (include "name" .) .volumeName -}}
{{- end -}}

{{- define "appPlatform.twoStepInstall" -}}
{{- $is_chart_operator := lookup "application.giantswarm.io/v1alpha1" "Chart" "giantswarm" "chart-operator" -}}
{{- $is_chart_operator_bad := true }}
{{- if $is_chart_operator }}
{{- $is_chart_operator_bad = (semverCompare "< 2.31.0-0" $is_chart_operator.spec.version) }}
{{- end }}

{{- $is_this_chart_cr := lookup "application.giantswarm.io/v1alpha1" "Chart" "giantswarm" . -}}
{{- $is_outside_app_platform := true }}
{{- if $is_this_chart_cr }}
{{- $is_outside_app_platform = false }}
{{- end }}

{{- if or $is_chart_operator_bad $is_outside_app_platform }}
{{- print "unsupported: true" -}}
{{- else -}}
{{- print "unsupported: false" -}}
{{- end -}}
{{- end -}}


{{/*
VPA settings for each controller
*/}}

{{- define "resource.vpa.enabled" -}}
{{- if and (or (.Capabilities.APIVersions.Has "autoscaling.k8s.io/v1") (.Values.verticalPodAutoscaler.force)) (.Values.verticalPodAutoscaler.enabled) }}true{{ else }}false{{ end }}
{{- end -}}

{{- define "resources.helmController" -}}
requests:
{{ toYaml .Values.resources.helmController.requests | indent 2 -}}
{{ if eq (include "resource.vpa.enabled" .) "false" }}
limits:
{{ toYaml .Values.resources.helmController.limits | indent 2 -}}
{{- end -}}
{{- end -}}

{{- define "resources.imageAutomationController" -}}
requests:
{{ toYaml .Values.resources.imageAutomationController.requests | indent 2 -}}
{{ if eq (include "resource.vpa.enabled" .) "false" }}
limits:
{{ toYaml .Values.resources.imageAutomationController.limits | indent 2 -}}
{{- end -}}
{{- end -}}

{{- define "resources.imageReflectorController" -}}
requests:
{{ toYaml .Values.resources.imageReflectorController.requests | indent 2 -}}
{{ if eq (include "resource.vpa.enabled" .) "false" }}
limits:
{{ toYaml .Values.resources.imageReflectorController.limits | indent 2 -}}
{{- end -}}
{{- end -}}

{{- define "resources.kustomizeController" -}}
requests:
{{ toYaml .Values.resources.kustomizeController.requests | indent 2 -}}
{{ if eq (include "resource.vpa.enabled" .) "false" }}
limits:
{{ toYaml .Values.resources.kustomizeController.limits | indent 2 -}}
{{- end -}}
{{- end -}}

{{- define "resources.notificationController" -}}
requests:
{{ toYaml .Values.resources.notificationController.requests | indent 2 -}}
{{ if eq (include "resource.vpa.enabled" .) "false" }}
limits:
{{ toYaml .Values.resources.notificationController.limits | indent 2 -}}
{{- end -}}
{{- end -}}

{{- define "resources.sourceController" -}}
requests:
{{ toYaml .Values.resources.sourceController.requests | indent 2 -}}
{{ if eq (include "resource.vpa.enabled" .) "false" }}
limits:
{{ toYaml .Values.resources.sourceController.limits | indent 2 -}}
{{- end -}}
{{- end -}}

{{ define "podTemplateAnnotations.kustomizeController" }}
{{- printf "prometheus.io/port: \"8080\"" | nindent 8 -}}
{{- printf "prometheus.io/scrape: \"true\"" | nindent 8 }}
{{- if (.Values.kustomizeController.podTemplate.annotations) -}}
{{- range $k, $v := .Values.kustomizeController.podTemplate.annotations }}
{{- $k | nindent 8 }}: {{ $v }}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "podTemplateLabels.kustomizeController" -}}
{{- printf "app: kustomize-controller" | nindent 8 -}}
{{- printf "app.kubernetes.io/instance: %s" ( .Release.Name ) | nindent 8 }}
{{- printf "app.kubernetes.io/managed-by: %s" ( .Release.Service ) | nindent 8 }}
{{- printf "app.kubernetes.io/name: %s" ( include "name" . ) | nindent 8 }}
{{- printf "app.kubernetes.io/version: %s" ( .Chart.AppVersion ) | nindent 8 }}
{{- printf "giantswarm.io/service_type: managed" | nindent 8 }}
{{- printf "helm.sh/chart: %s" ( include "chart" . ) | nindent 8 }}
{{- if (.Values.kustomizeController.podTemplate.labels) -}}
{{- range $k, $v := .Values.kustomizeController.podTemplate.labels }}
{{- $k | nindent 8 }}: {{ $v | quote }}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Generate feature gates argument
*/}}
{{- define "imageAutomationController.featureGates" -}}
{{- $arg := "" }}
{{- range $k := .Values.imageAutomationController.featureGatesToDisable -}}
{{- $arg = (printf "%s%s=false," $arg $k) }}
{{- end -}}
{{- trimSuffix "," (printf $arg) }}
{{- end -}}

{{/*
Generate Kustomize Controller SA's annotations
*/}}
{{- define "kustomizeControllerSA.annotations" -}}
{{- if not (.Values.kustomizeServiceAccount.annotations) }}
{{- printf "{}" }}
{{- else }}
{{- range $k, $v := .Values.kustomizeServiceAccount.annotations }}
{{- $k | nindent 4 }}: {{ $v | quote }}
{{- end -}}
{{- end -}}
{{- end }}

{{/*
Define name of the PriorityClass.
*/}}
{{- define "priorityClass.name" -}}
{{- if .Values.priorityClass.name }}
{{- .Values.priorityClass.name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Namespace .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
