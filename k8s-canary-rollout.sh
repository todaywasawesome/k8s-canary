#!/bin/bash

#Our istio update loop

healthcheck(){
	echo "Starting Heathcheck"
	h=true
	#Start custom healthcheck
	output=$(kubectl get pods -l app="$CANARY_HOST_NAME" -n canary --no-headers)
	s=($(echo "$output" | awk '{s+=$4}END{print s}'))
	c=($(echo "$output" | wc -l))

	if [ "$s" -gt "2" ]; then
		h=false
	fi
	#End custom healthcheck
	if [ ! $h == true ]; then
		cancel
		echo "Exit failed"
	else
		echo "Service healthy."
	fi
}

cancel(){
	echo "Cancelling rollout"
	m="cancel"
	#Add rollback kubectl apply
    echo "Canary removed from network."
    exit 1
}

incrementservice(){
	#Pass $1 = canary traffic increment

	#Calulate increments. N = the number of starting pods, I = Increment value, X = how many pods to add
	# x / (N + x) = I 
	# Starting pods N = 5
	# Desired increment I = 0.35
	# Solve for X
	# X / (5+X)= 0.35
	# X = .35(5+x)
	# X = 1.75 + .35x
	# X-.35X=1.75
	# .65X = 1.75
	# X = 35/13
	# X = 2.69
	# X = 3
	# 5+3 = 8 #3/8 = 37.5%
	# Round		A 	B
	# 1			5	3
	# 2			2	6
	# 3			0	5

	m=$1
	echo "Creating $WORKING_VOLUME/canary_$m.yml ..."
	cp istio/canary.yml $WORKING_VOLUME/canary_$m.yml
	
    COUNTER=0
    until [ $COUNTER -ge 30 ]; do echo -n "."; sleep 1; let COUNTER+=1; done
    echo "Traffic mix updated to $m% for canary."
}

mainloop(){
	#Copy old deployment with new image, set replicas to 1
	echo "kubectl get deployment $PROD_DEPLOYMENT -n $NAMESPACE -o=yaml > $WORKING_VOLUME/canary_deployment.yaml"
	kubectl get deployment $PROD_DEPLOYMENT -n $NAMESPACE -o=yaml > $WORKING_VOLUME/canary_deployment.yaml
	NAME=$(kubectl get deployment $PROD_DEPLOYMENT -n $NAMESPACE -o=jsonpath='{.metadata.name}')
	IMAGE=$(kubectl get deployment colors -n k8s -o=yaml | grep image: | sed -E 's/.*image: (.*)/\1/')
	STARTING_REPLICAS=$(kubectl get deployment $PROD_DEPLOYMENT -n $NAMESPACE --no-headers | awk '{print $2}')

	#Replace old name with new
	sed -Ei '' "s/name\: $PROD_DEPLOYMENT/name: $CANARY_DEPOLOYMENT/g" $WORKING_VOLUME/canary_deployment.yaml

	#Replace image
	sed -Ei '' "s#image: $IMAGE#image: $CANARY_IMAGE#g" $WORKING_VOLUME/canary_deployment.yaml

	#Apply new deployment
	kubectl apply -f $WORKING_VOLUME/canary_deployment.yaml -n $NAMESPACE

	CANARY_REP=0

	healthcheck

	# while [ $TRAFFIC_INCREMENT -lt 100 ]
	# do
	# 	p=$((p + $TRAFFIC_INCREMENT))
	# 	if [ "$p" -gt "100" ]; then
	# 		p=100
	# 	fi
	# 	incrementservice $p

	# 	if [ "$p" == "100" ]; then
	# 		echo "Done"
	# 		exit 0
	# 	fi
	# 	sleep 50s
	# 	healthcheck
	# done
}

if [ "$1" != "" ] && [ "$2" != "" ] && [ "$3" != "" ] && [ "$4" != "" ] && [ "$5" != "" ]; then
	echo "Volume Set"
	WORKING_VOLUME=${1%/}
	PROD_DEPLOYMENT=$2
	CANARY_DEPOLOYMENT=$3
	TRAFFIC_INCREMENT=$4
	NAMESPACE=$5
	CANARY_IMAGE=$6
else
	#echo instructions
	echo "USAGE\n rollout.sh [WORKING_VOLUME] [CURRENT_HOST_NAME] [CANARY_HOST_NAME] [TRAFFIC_INCREMENT]"
	echo "\t [WORKING_VOLUME] - This should be set with \${{CF_VOLUME_PATH}}"
	echo "\t [PROD_DEPLOYMENT] - The name of the service currently receiving traffic from the Istio gateway"
	echo "\t [CANARY_DEPOLOYMENT] - The name of the new service we're rolling out."
	echo "\t [TRAFFIC_INCREMENT] - Integer between 1-100 that will step increase traffic"
	echo "\t [NAMESPACE] - Namespace of the application"
	echo "\t [CANARY_IMAGE] - New image url, must use same pull secret"
	exit 1;
fi

echo $BASH_VERSION
p=0
mainloop
