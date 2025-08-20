---
title: {{ getenv "HUGO_TITLE" | default (replace .Name "-" " " | title) }}
subtitle: 
author: {{ getenv "HUGO_AUTHOR" | default "admin" }}
type: page
date: {{ .Date }}
tags:
{{- range (split (getenv "HUGO_TAG" | default "Untaged") ",") }}
  - {{ trim . " " }}
{{- end }}
---