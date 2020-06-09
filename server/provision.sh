#! /usr/bin/zsh -e

export CACHE_DIR=/var/cache/umec

#########################################################################################
# Functions

install_command() {
	local command=$1
	local url=$2
	if ! type "$command" > /dev/null ; then
	       	if ! [[ -e $CACHE_DIR/install_$command ]] ; then
	       		echo "Fetching $command installation script"
		 	curl -L $2 -o $CACHE_DIR/install_$command
	       	fi
       		chmod u+x $CACHE_DIR/install_$command
 		echo "Installing $command"
		$CACHE_DIR/install_$command
	fi
}

add_to_env() {
	local var=$(echo $1 | tr --delete "[:space:]")
	local val=$(echo $2 | tr --delete "[:space:]")
	for d in "/home/vagrant" "/root" 
	{ 
		grep "export $var=$val" "$d/.profile" || echo "export $var=$val" >> $d/.profile
	}
	export $var=$val
}

#########################################################################################
# Install potentially missing packages and other housekeeping

pacman -Syu --noconfirm --needed containerd curl which
mkdir --parents --verbose $CACHE_DIR
touch /home/vagrant/.profile
touch /root/.profile
add_to_env "TERM" "xterm-256color"

#########################################################################################
# Add /usr/local/bin to path if it is not there already
if ! [[ $PATH =~ "/usr/local/bin" ]] ; then
	echo "Adding /usr/local/bin to path"
	export PATH=$PATH:/usr/local/bin
fi


#########################################################################################
# Install k3s

install_command k3s "https://get.k3s.io" 
add_to_env "KUBECONFIG" "/etc/rancher/k3s/k3s.yaml"
cp --force $KUBECONFIG /app/
cp --force /var/lib/rancher/k3s/server/node-token /app/


#########################################################################################
# Install helm
# https://github.com/openfaas/faas-netes/blob/master/HELM.md

install_command helm "https://raw.githubusercontent.com/kubernetes/helm/master/scripts/get"

kubectl -n kube-system get sa | grep tiller || \
	kubectl -n kube-system create sa tiller

kubectl get clusterrolebinding | grep tiller || \
kubectl create clusterrolebinding tiller --clusterrole cluster-admin --serviceaccount=kube-system:tiller

# This is from https://stackoverflow.com/questions/45914420/why-tiller-connect-to-localhost-8080-for-kubernetes-api#47201852
# Otherwise, helm init will try to access port 8080 on localhost which is wrong
mkdir --parents --verbose .kube/
kubectl config view --raw > /root/.kube/config

helm init --skip-refresh --upgrade --service-account tiller


#########################################################################################
# Install openfaas with helm
# https://github.com/openfaas/faas-netes/blob/master/chart/openfaas/README.md

kubectl apply -f $CACHE_DIR/namespaces.yml
helm repo add openfaas https://openfaas.github.io/faas-netes/

# generate a random password
if [ -z $PASSWORD ] ; then
	PASSWORD=$(head -c 12 /dev/urandom | shasum| cut -d' ' -f1)
	echo $PASSWORD >> password
	add_to_env "PASSWORD" $PASSWORD
fi

# We use kubectl apply since it is idempotent

cat <<EOF > secrets.yaml
apiVersion: v1
kind: Secret
metadata:
  name: basic-auth
type: Opaque
stringData:
  username: admin
  password: $PASSWORD
EOF

kubectl -n openfaas apply -f secrets.yaml

kubectl -n kube-system wait --for=condition=Ready pod -l name=tiller --timeout=300s

helm repo update
helm upgrade openfaas --install openfaas/openfaas \
    --namespace openfaas  \
    --set basic_auth=true \
    --set functionNamespace=openfaas-fn

add_to_env "OPENFAAS_PORT" \
	"$(kubectl get svc -n openfaas gateway-external --output=yaml | awk -F ":" '/ nodePort/ {print $2}')"

add_to_env "OPENFAAS_URL" \
	"http://127.0.0.1:$OPENFAAS_PORT"


#########################################################################################
# Install openfaas-cli

install_command "faas-cli" "https://cli.openfaas.com"
