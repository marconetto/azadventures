## Quick intro on containers and Azure Container Instances (ACI) example
This tutorial aims at giving a quick intro on containers, where they can be
used in Azure, and an example of a container-based deployment using Azure
Container Instances (ACI) service.

**GitHub Pages: [Here](https://marconetto.github.io/azadventures/chapter13/)**

## What are containers

Containers refer to a lightweight, portable, and self-sufficient unit of
software that puts together code and all its dependencies so one can run an
application.

Virtual machine (VM)s virtualize the underlying hardware so that multiple
operating system (OS) instances can run on that hardware. Each VM runs an OS and
has access to virtualized resources representing the underlying hardware. On the
other hand, a container virtualizes the underlying OS and causes the
containerized app to perceive that it has the OS---including CPU, memory, file
storage, and network connections---all to itself. Besides, containers share the
host OS, so they do not need to boot an OS. So contenarized applications can
start much faster. More details
[here](https://azure.microsoft.com/en-us/resources/cloud-computing-dictionary/what-is-a-container).

In Azure, containers can be used in multiple services, including [Azure
Container Instances
(ACI)](https://learn.microsoft.com/en-us/azure/container-instances/), [Azure
Kubernetes Service (AKS)](https://learn.microsoft.com/en-us/azure/aks/), [Azure
Container
Apps](https://learn.microsoft.com/en-us/azure/container-apps/overview), [Azure
Batch](https://learn.microsoft.com/en-us/azure/batch/batch-docker-container-workloads),
among others.


There are several container runtimes available out there, including
[Docker](https://www.docker.com/), [Podman](https://podman.io/),
[containerd](https://containerd.io/), [Apptainer
(Singularity)](https://apptainer.org/).


## End-2-end hello world in azure containers

Assuming one has docker installed.

Example from [here](https://learn.microsoft.com/en-us/azure/container-instances/container-instances-tutorial-prepare-app)

```
git clone https://github.com/Azure-Samples/aci-helloworld.git

docker build ./aci-helloworld -t aci-tutorial-app

docker images
```

Run the docker container locally:

```
docker run -d -p 8080:80 aci-tutorial-app
```

Open browser with `http://localhost:8080`.

You can delete the running container by using `docker ps` to get the container
id and `docker container kill <id>`


Moving to the creation of an Azure Container Registry.

```
az group create --name myResourceGroup --location eastus
az acr create --resource-group myResourceGroup --name <acrName> --sku Basic
```

Login to acr, get its full login name, tag local docker container image with
the container registry full login name, and push the image. Then list the images
in the container registry.

```
az acr login --name <acrName>
loginserver=$(az acr show --name <acrName> --query loginServer --output tsv)
docker tag aci-tutorial-app $loginserver/aci-tutorial-app:v1
docker push <acrLoginServer>/aci-tutorial-app:v1
az acr repository list --name <acrName> --output table
```



```
az container create --resource-group myResourceGroup \
                    --name aci-tutorial-app \
                    --image $loginserver/aci-tutorial-app:v1 \
                    --cpu 1 --memory 1 --registry-login-server $loginserver \
                    --registry-username <service-principal-ID> --registry-password <service-principal-password> --ip-address Public --dns-name-label <aciDnsLabel> --ports 80
```

To get the fqdn to be used to open the app in the browser:

```
az container show --resource-group myResourceGroup --name aci-tutorial-app --query ipAddress.fqdn
```

You can user the browser with the fqnd to check the container app running. Once
it is done, you can delete the resource group:

```
az group delete --name myResourceGroup
```

notes:
- `--dns-name-label`: should be unique within the Azure region you create the
  container instance
- `--registry-password`: can be obtained using `az acr credential show --name
  <registry>`
- `--registry-username`: that is the registry name (default), or use this the
  same command used to get the password above.


## References
- Container definition: <https://azure.microsoft.com/en-us/resources/cloud-computing-dictionary/what-is-a-container>

