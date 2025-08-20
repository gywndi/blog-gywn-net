---
title: {{ getenv "HUGO_TITLE" | default (replace .Name "-" " " | title) }}
subtitle: 
author: {{ getenv "HUGO_AUTHOR" | default "admin" }}
type: post
date: {{ .Date }}
url: {{ .Date |  time.Format "2006/01" }}/{{ .File.ContentBaseName }}
categories:
{{- range (split (getenv "HUGO_CATEGORY" | default "Uncategorized") ",") }}
  - {{ trim . " " }}
{{- end }}
tags:
{{- range (split (getenv "HUGO_TAG" | default "Untagged") ",") }}
  - {{ trim . " " }}
{{- end }}
---

