# Hyperledger Kubernetes For Google Kubernetes Engine
[![Google Cloud](https://deepchains.files.wordpress.com/2017/12/hyperlegerlogo.png?w=400)](https://www.hyperledger.org)

[![Magic leap](https://res.cloudinary.com/dww6hce3q/image/upload/c_scale,w_235/v1578606946/Magic_Leap_jgpl4o.png)](https://www.magicleap.com) [![Magic leap](https://res.cloudinary.com/dww6hce3q/image/upload/c_scale,w_190/v1578607063/unnamed_vjsgpe.png)](http://www.kaizentek.io)

[![Build Status](https://travis-ci.org/joemccann/dillinger.svg?branch=master)](https://travis-ci.org/joemccann/dillinger)

## Created By:
John Radosta - [KaizenTek](http://www.kaizentek.io)

Benjamin Beckman - [Magic Leap](http://www.magicleap.com)

## Acknowledgements
Special thank you to John Campbell & Gary Davidson and the rest of the team at Magic Leap for giving us the go-ahead to opensource this endeavor. 

## Requirements
You'll need to have a Kubernetes cluster running on GCP with Helm and Tiller both installed (with the proper service account and cluster role binding for tiller) For instructions on how to install Helm and Tiller, you can check out this resource.

[Setting Up Helm & Tiller](http://docs.shippable.com/deploy/tutorial/deploy-to-gcp-gke-helm/)

## Before You Deploy

You'll need to install CouchDB as a StatefulSet running on the cluster so the peers can communicate with CouchDB as opposed to LevelDB. This allows for rich queries on JSON objects stored in CouchDB versus only primary index range and partial composite ranges. If you want to use LevelDB as the state database which does not support in-depth rich querying (simple key-value pairs only), you can skip to the Using LevelDB section. 

### Installing CouchDB (Default Deployment Setting)

1. Create a kubernetes secret, replace the values in quotes with your own values:

    ```
    $ kubectl create secret generic cluster-couchdb \
      --from-literal=adminUsername=(YOUR_USERNAME) \
      --from-literal=adminPassword=(YOUR_PASSWORD) \
      --from-literal=cookieAuthSecret=(YOUR_PASSWORD)
    ```

2. Add the CouchDB Helm Repo:

    ```
    $ helm repo add couchdb https://apache.github.io/couchdb-helm
    ```

3. Install CouchDB w/ Helm, replace the (YOUR_) fileds with your custom values that you set above, but DO NOT change the release name:

    ```
    $ helm install \
      --name cluster \
      --set createAdminSecret=false \
      --set adminUsername=(YOUR_USERNAME) \
      --set adminPassword=(YOUR_PASSWORD) \
      --set cookieAuthSecret=(YOUR_PASSWORD) \
      --set couchdbConfig.couchdb.uuid=$(curl https://www.uuidgenerator.net/api/version4 2>/dev/null | tr -d -) \
      --set persistentVolume.enabled=true \
      --set persistentVolume.size=50Gi \
      couchdb/couchdb
    ```
    
### To Use LevelDB 
Change the CORE_LEDGER_STATE_STATEDATABASE environment variable to LevelDB for each of the four peers in "configFiles/peersDeployment.yaml":

```
- name: CORE_LEDGER_STATE_STATEDATABASE
  value: LevelDB 
```

## Organizations Configuration
All the configuration for each peer organization can be found and configured to your liking in artifacts/configtx.yaml and artifacts/crypto-config.yaml

## Installation

NOTE: You will need to set your zone/region to us-east1-b for the installation to run correctly, if you want to launch the network in a cluster operating in another region, you'll need to replace all values of us-east1-b to whatever region you are using.

Make sure you have your cluster credentials handed to kubectl using the command:

```
$ gcloud container clusters get-credentials CLUSTER_NAME --region REGION
```

Run the setup_blockchainNetwork.sh script with the zone of your kubernetes cluster as an argument (this is required). The script will automatically created a network file server on Kubernetes backed by a persistent disk. This is needed for the peers to be able to write to the same shared disk. 

```
$ ./setup_blockchainNetwork.sh us-east1-b
```

Let the script run, if you run into any issues, just run the deleteNetwork.sh script and re-run the deploy script. Again, you'll need to pass the GCP zone your cluster is deployed in as an argument. If you run into an error deleting the nfs-disk, then just run the delete script twice. 

```
$ ./deleteNetwork.sh us-east1-b
```

## Test The deployed network

After successful execution of the script `setup_blockchainNetwork.sh`, check the status of pods.

```
$ kubectl get pods
NAME                                    READY     STATUS    RESTARTS   AGE
blockchain-ca-7848c48d64-2cxr5          1/1       Running   0          4m
blockchain-orderer-596ccc458f-thdgn     1/1       Running   0          4m
blockchain-org1peer1-747d6bdff4-4kzts   1/1       Running   0          4m
blockchain-org2peer1-7794d9b8c5-sn2qf   1/1       Running   0          4m
blockchain-org3peer1-59b6d99c45-dhtbp   1/1       Running   0          4m
blockchain-org4peer1-6b6c99c45-wz9wm    1/1       Running   0          4m
```

The script joins all peers on one channel `channel1`, install chaincode on all peers and instantiate chaincode on channel1. It means we can execute an invoke/query command on any peer and the response should be same on all peers. 

Please note that in this pattern tls certs are disabled to avoid complexity. In this pattern, the CLI commands are used to test the network. For running a query against any peer, you need to get into a bash shell of a peer, run the query and exit from the peer container.

Use the following command to get into a shell of a peer:

  ```
  $ kubectl exec -it <blockchain-org1peer1 pod name> sh
  ```

And the command to be used to exit from the peer container is:

  ```
  # exit
  ```


## Chaincode Deployment Example (Golang)
Instead of manually installing and updating chaincode on each peer, there is an example chaincode with K8s job templates that will deploy chaincode with any CI/CD tool of your choice. To deploy the sample chaincode:

Note: Your CI/CD system will need to have a service account activated with sufficient privileges to deploy to your K8s cluster: 

### Chaincode Deployer Continuous Integration/Deployment Instructions:
We needed to create a way that allowed us to continuously deploy and upgrade chaincode in an enterprise setting, so we created a series of sequential Kubernetes jobs that automatically install, instantiates, and upgrades chaincode from a single script. 

The Chaincode Deployer (chaincode_deployer directory) should be separated into its own repo for each chaincode you plan to deploy (chaincode.go). Then you can just use whatever CI/CD tooling you'd like to run the deploy.sh script in the chaincode_deployer directory. Below is a step by step usage guide, there is an example chaincode for a simple asset that you can run to test how it works. 

    1) Write  your chaincode in 'chaincode_deployer/chaincode/' directory. All your code must be scoped to 'package main' or you will get $GOPATH errors in your peer when the install job runs.

    2) In 'chaincode_deployer/chaincode/k8s/chaincode_config.template', give your chaincode a name, a version number and an initial key-value state under the "data" section of the template file. IMPORTANT: You will need to increment the chaincode-version number everytime you are upgrading your chaincode, or both the upgrade and instantiate chaincode jobs will fail. 

    3) Have your CI/CD system run the ./deploy.sh script in the chaincode_deployer directory. That's it!

The chaincode deploy script will sequentially create Kubernetes jobs to install and then either instantiate or upgrade your chaincode. First, it will try to upgrade any chaincode of the same name you're deploying, and if that job fails, it will automatically failover to instantiating a new chaincode. 

Hyperledger for Google Kubernetes Engine uses a number of technologies to work properly:

* [Google Cloud] - Google's cloud service 
* [Kubernetes Engine] - Container orchestration engine
* [Hyperledger Fabric] - Private enterprise blockchain built on Raft protocol 
* [CouchDB] - JSON document storage database
* [Golang] - Golang is a statically typed, compiled programming language designed at Google

   [Hyperledger Fabric]: <https://www.hyperledger.org>
   [Google Cloud]: <https://cloud.google.com>
   [Kubernetes Engine]: <http://kubernetes.io>
   [CouchDB]: <http://couchdb.apache.org>
   [Golang]: <http://www.golang.org>

## License
This code pattern is licensed under the Apache Software License, Version 2.  Separate third party code objects invoked within this code pattern are licensed by their respective providers pursuant to their own separate licenses. Contributions are subject to the [Developer Certificate of Origin, Version 1.1 (DCO)](https://developercertificate.org/) and the [Apache Software License, Version 2](https://www.apache.org/licenses/LICENSE-2.0.txt).

[Apache Software License (ASL) FAQ](https://www.apache.org/foundation/license-faq.html#WhatDoesItMEAN)