#!/bin/bash
JOB_ID=$(cat /dev/random | LC_CTYPE=C tr -dc "a-z0-9" | head -c 12)
sed "s/#JOB_ID/${JOB_ID}/" ./k8s/copy_chaincode.template > ./k8s/copy_chaincode-${JOB_ID}.yaml &
sed "s/#JOB_ID/${JOB_ID}/" ./k8s/chaincode_config.template > ./k8s/chaincode_config-${JOB_ID}.yaml &
sed "s/#JOB_ID/${JOB_ID}/" ./k8s/chaincode_install.template > ./k8s/chaincode_install-${JOB_ID}.yaml &
sed "s/#JOB_ID/${JOB_ID}/" ./k8s/chaincode_instantiate.template > ./k8s/chaincode_instantiate-${JOB_ID}.yaml &
sed "s/#JOB_ID/${JOB_ID}/" ./k8s/chaincode_upgrade.template > ./k8s/chaincode_upgrade-${JOB_ID}.yaml 


sleep 5

kubectl create -f ./k8s/copy_chaincode-${JOB_ID}.yaml 
sleep 5
pod=$(kubectl get pods --selector=job-name=copychaincode-${JOB_ID} --output=jsonpath={.items..metadata.name})
podSTATUS=$(kubectl get pods --selector=job-name=copychaincode-${JOB_ID} --output=jsonpath={.items..phase})

while [ "${podSTATUS}" != "Running" ]; do
    echo "Wating for container of copy chaincodepod to run. Current status of ${pod} is ${podSTATUS}"
    sleep 5;
    if [[ "${podSTATUS}" == *"Error"* ]]; then
        echo "There is an error in copychaincode-${JOB_ID} job. Please check logs."
        exit 1
    fi
    podSTATUS=$(kubectl get pods --selector=job-name=copychaincode-${JOB_ID} --output=jsonpath={.items..phase})
done

kubectl cp ./chaincode $pod:/shared/artifacts/${JOB_ID}

echo "Waiting for 15 more seconds for copying chaincode to avoid any network delay..."
echo "Done!"
sleep 15

JOBSTATUS=$(kubectl get jobs |grep "copychaincode-${JOB_ID}" | awk '{print $2}')

while [ "${JOBSTATUS}" != "1/1" ]; do
    echo "Waiting for copychaincode-${JOB_ID} job to complete"
    sleep 1;
    PODSTATUS=$(kubectl get pods | grep "copychaincode-${JOB_ID}" | awk '{print $3}')
        if [[ "${PODSTATUS}" == *"Error"* ]]; then
            echo "There is an error in copychaincode-${JOB_ID} job. Please check logs. Exiting..."
            exit 1
        fi
    JOBSTATUS=$(kubectl get jobs |grep "copychaincode-${JOB_ID}" | awk '{print $2}')
done

echo "Copy chaincode job completed!"

echo "Creating chaincode configmap..."
kubectl create -f ./k8s/chaincode_config-${JOB_ID}.yaml 
echo "Config map created!"

echo "Creating installchaincode job..."
kubectl create -f ./k8s/chaincode_install-${JOB_ID}.yaml 

JOBSTATUS=$(kubectl get jobs | grep chaincodeinstall-${JOB_ID} | awk '{print $2}')

while [ "${JOBSTATUS}" != "1/1" ]; do
    echo "Waiting for chaincodeinstall job to be completed..."
    sleep 1;
    if [[ "$(kubectl get pods | grep chaincodeinstall-${JOB_ID} | awk '{print $3}')" == *"Error"* ]]; then
        echo "Chaincode Install Failed! Cleaning up and Exiting..."
        kubectl delete job copychaincode-${JOB_ID}
        kubectl delete cm chaincode-config-${JOB_ID}
        exit 1
    fi
    JOBSTATUS=$(kubectl get jobs | grep chaincodeinstall-${JOB_ID} |awk '{print $2}')
done

echo "Chaincode Install Completed Successfully!"


# upgrade chaincode on channel
echo "Creating Chaincode Upgrade/Instantiate job(s)..."
kubectl create -f ./k8s/chaincode_upgrade-${JOB_ID}.yaml 

JOBSTATUS=$(kubectl get jobs | grep chaincodeupgrade-${JOB_ID} | awk '{print $2}')
while [ "${JOBSTATUS}" != "1/1" ]; do
    echo "Waiting for chaincodeupgrade job to be completed"
    sleep 1;
    
    if [[ "$(kubectl get pods | grep chaincodeupgrade-${JOB_ID} | awk '{print $3}')" == *"Error"* ]]; then
        echo "Chaincode Upgrade Failed! Attempting to instantiate chaincode instead..."
        kubectl create -f ./k8s/chaincode_instantiate-${JOB_ID}.yaml 
        JOBSTATUS=$(kubectl get jobs | grep chaincodeinstantiate-${JOB_ID} | awk '{print $2}')

        while [ "${JOBSTATUS}" != "1/1" ]; do
            echo "Waiting for chaincodeinstantiate-${JOB_ID} job to be completed..."
            sleep 1;
            if [[ "$(kubectl get pods | grep chaincodeinstantiate-${JOB_ID} | awk '{print $3}')" == *"Error"* ]]; then
                echo "Chaincode Instantiate Failed! Cleaning up and Exiting..."
                kubectl delete job chaincodeinstall-${JOB_ID}
                kubectl delete job copychaincode-${JOB_ID}
                kubectl delete cm chaincode-config-${JOB_ID}
                kubectl delete job chaincodeupgrade-${JOB_ID}
                exit 1
            fi
            JOBSTATUS=$(kubectl get jobs | grep chaincodeinstantiate-${JOB_ID} | awk '{print $2}')
        done
        break
    fi

    JOBSTATUS=$(kubectl get jobs | grep chaincodeupgrade-${JOB_ID} | awk '{print $2}')
done

echo "Chaincode Upgrade/Instantiate Completed Successfully. Chaincode successfully deployed! Cleaning up and exiting..."
kubectl delete job chaincodeinstall-${JOB_ID}
kubectl delete job copychaincode-${JOB_ID}
kubectl delete cm chaincode-config-${JOB_ID}
kubectl delete job chaincodeupgrade-${JOB_ID}
kubectl delete job chaincodeinstantiate-${JOB_ID}
sleep 1
