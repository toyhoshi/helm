# SRE Labs

This repository contains:
- the source code to implement a standalone HTTP web application
- a dockerfile to containerize the service
- an helm chart for the service
- an helm chart to install kube-prometheus-stack with an easy example of dashboard and alert
- a script to automate the provisioning of a local Kubernetes cluster

## Requirements
You should have installed at least:
- Docker
- Python 3.10+

Generate python requirements using pip freeze, more important are:
- pip install flask
- pip install waitress
- pip install prometheus-client

## Build image
To containerize the service we have build image and push it on dockerhub:
```bash 
docker build --network=host -t sre-labs-webapp .
docker tag 7afd1b4bec75 toyhoshi/sre-labs-webapp:0.1
docker push toyhoshi/sre-labs-webapp:0.1
```

## Project brief

### Source code
To implement the standalone HTTP web application I use Python, specifically using: Flask, SQLite, Prometheus-client.

- API are exposed using @app.route definitions, a Python decorator that Flask provides to assign URLs in our app to functions easily.
- Server return JSON payload using json module in Python.
- Metadata is stored on a file-based SQL database, create a connection to a SQLite database, add a table to that database, insert data into that table, and read data in that table.
- Three types of prometheus metric are offered: Counter, Gauge, Summary

### Running the application
To verify that our service is working you can choose:
- python: python3 webapp/srvpro.py
- docker (docker push toyhoshi/sre-labs-webapp:0.4): docker run -p 8080:8080 -it sre-labs-webapp
- kubernetes: 
    - export NODE_PORT=$(kubectl get --namespace sre-labs -o jsonpath="{.spec.ports[0].nodePort}" services sre-labs-webapp-sre-labs-webapp-chart)
    - export NODE_IP=$(kubectl get nodes --namespace sre-labs -o jsonpath="{.items[0].status.addresses[0].address}")
    - echo http://$NODE_IP:$NODE_PORT

### Example
You'll be able to access the application from [http://localhost:8080](http://localhost:8080) or for example from [http://172.18.0.4:31722](http://172.18.0.4:31722) if you use kubernetes.

```bash
❯ docker run -p 8080:8080 -it sre-labs-webapp
Initialized the database and starting server on port 8080

❯ curl -F file=@oracle-dublin-office2.1.jpeg http://localhost:8080/image
{
    "id": "0e1ad368-10b6-4ee8-a468-0a7d5acab55d",
    "name": "oracle-dublin-office2.1.jpeg",
    "image": 138049,
    "timestamp": "2022-02-17T07:55:39+00:00"
}

❯ curl http://localhost:8080/image/0e1ad368-10b6-4ee8-a468-0a7d5acab55d
{
    "id": "0e1ad368-10b6-4ee8-a468-0a7d5acab55d",
    "name": "oracle-dublin-office2.1.jpeg",
    "image": 138049,
    "timestamp": "2022-02-17T07:55:39+00:00"
}

# try wrong uuid
❯ curl http://localhost:8080/image/0e1ad368-10b6-4ee8-0000-0a7d5acab55d
{
    "id": "There are no results for this id"
}

# load another image same size
❯ curl -F file=@oracle-dublin-office2.2.jpeg http://localhost:8080/image

❯ curl http://localhost:8080/image/duplicates
[
    {
        "id": "0e1ad368-10b6-4ee8-a468-0a7d5acab55d",
        "name": "oracle-dublin-office2.1.jpeg",
        "image": 138049,
        "timestamp": "2022-02-17T07:55:39+00:00"
    },
    {
        "id": "d4b2eaf5-72de-4df0-a796-beced292ad8e",
        "name": "oracle-dublin-office2.2.jpeg",
        "image": 138049,
        "timestamp": "2022-02-17T07:59:57+00:00"
    }
]

# metrics endpoint
❯ curl http://localhost:8080/metrics
# HELP python_gc_objects_collected_total Objects collected during gc
# TYPE python_gc_objects_collected_total counter
python_gc_objects_collected_total{generation="0"} 278.0
...
# HELP request_count_total App Request Count
# TYPE request_count_total counter
request_count_total{app_name="webapp",endpoint="/image",http_status="200",method="POST"} 2.0
request_count_total{app_name="webapp",endpoint="/image/0e1ad368-10b6-4ee8-a468-0a7d5acab55d",http_status="200",method="GET"} 1.0
...
# HELP SRE_requests_total Application Request Count
# TYPE SRE_requests_total counter
SRE_requests_total{endpoint="/image"} 2.0
SRE_requests_total{endpoint="/image/<id>"} 2.0
SRE_requests_total{endpoint="/image/duplicates"} 1.0
...
# HELP SRE_last_request_time Last request start time
# TYPE SRE_last_request_time gauge
SRE_last_request_time 1.6450848135148926e+09
# HELP SRE_last_response_time Last request serve time
# TYPE SRE_last_response_time gauge
SRE_last_response_time 1.645084797548377e+09
# HELP SRE_latency_seconds Time to serve
# TYPE SRE_latency_seconds summary
SRE_latency_seconds_count 2.0
SRE_latency_seconds_sum 0.0731363296508789
# HELP SRE_latency_seconds_created Time to serve
# TYPE SRE_latency_seconds_created gauge
SRE_latency_seconds_created 1.6450844993782878e+09
```

### About Docker image 
To containerize our service we start from python-alpine, this variant is useful when final image size being as small as possible is your primary concern. The main caveat to note is that it does use musl libc instead of glibc; the content of the Dockerfile is very basic, the application is not running as root.

Such an image usually introduces even a few vulnerabilities, a quick check with Snyk:

```bash
❯ snyk test --docker docker.io/toyhoshi/sre-labs-webapp:0.4

Testing docker.io/toyhoshi/sre-labs-webapp:0.4...
✗ Low severity vulnerability found in util-linux/libuuid
  Description: CVE-2021-3995

✗ Low severity vulnerability found in util-linux/libuuid
  Description: CVE-2021-3996

✗ Low severity vulnerability found in util-linux/libuuid
  Description: CVE-2022-0563

✗ Critical severity vulnerability found in expat/expat
  Description: Integer Overflow or Wraparound

✗ Critical severity vulnerability found in expat/expat
  Description: Integer Overflow or Wraparound
```


## Kubernetize the service
To use our service with Kubernetes we create an helm chart `sre-labs-webapp-chart` in addition we use a custom kube-prometheus-stack, which contains our sre-labs-dashboard.
Chart is very easy, we expose our service using service type `NodePort` so from outside the cluster we can call our service by requesting <NodeIP>:<NodePort>.
```bash
❯ export NODE_PORT=$(kubectl get --namespace sre-labs -o jsonpath="{.spec.ports[0].nodePort}" services sre-labs-webapp-sre-labs-webapp-chart)
❯ export NODE_IP=$(kubectl get nodes --namespace sre-labs -o jsonpath="{.items[0].status.addresses[0].address}")
❯ echo http://$NODE_IP:$NODE_PORT
❯ http://172.18.0.4:32226

❯ curl -F file=@oracle-dublin-office2.2.jpeg http://172.18.0.4:32226/image
``` 

### Prometheus and Grafana
Prometheus and Grafana are installed on a namespace called `monitoring` and we can open UI quite simply using `port-forward`, ie:
```bash
❯ kubectl --namespace monitoring port-forward svc/prometheus-grafana 8081:80 &
❯ kubectl --namespace monitoring port-forward svc/prometheus-kube-prometheus-prometheus 9090 &
```
We create a simple rule and alert:
```yaml
additionalPrometheusRulesMap:
  - groups:
      - name: SRE-alert-rules
        rules:
          - alert: TooMuchRequests
            expr: request_count_total > 10
            for: 1m
            labels:
              severity: error
            annotations:
              summary: "Too much requests (instance {{ $labels.target }})"
              description: "Probe failed\n  VALUE = {{ $value }}\n  LABELS: {{ $labels }}"
```
Connecto to prometheus UI, with url [http://localhost:9090](http://localhost:9090)
![Screenshot](assets/prometheus_alert.png)

Connect to Grafana UI, with url [http://localhost:8081](http://localhost:8081)
![Screenshot](assets/grafana_dashboard.png)

## Automate provisiong/deployment

### Local Kubernetes cluster
To spin up Kubernetes cluster we use simple bash script, we make a simplified version of [https://github.com/mateusmuller/kind-madeeasy](https://github.com/mateusmuller/kind-madeeasy). When the cluster is ready, the helm charts related to the service and to the prometheus stack are installed.


### Design
The design of everything from the cluster to the application is very basic: "keep it as simple as possible".

### It works ?
On principle it works. :-)

### Improvements
There are certainly improvements everywhere:
- Increase replica count, statefulsets
- Ingresss controller, load balancer, etc..
- Horizontal Pod Autoscaling...
- PodSecurityPolicy...
- Define "best" metrics: Response Time, Request Latency, Queued Time and Queue Size, CPU Usage, etc...
- Rules, alert, dashboard are really basic, but they show what can be done

## License
Sre-Labs is licensed under the **[MIT License](LICENSE)** (the "License"); you may not use this software except in compliance with the License.
