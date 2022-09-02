#!/bin/bash
set -e

LANG=C
SLEEP_SECONDS=45
ARGO_NS="openshift-gitops"
SEALED_SECRETS_FOLDER=components/operators/sealed-secrets-operator/overlays/default/
SEALED_SECRETS_SECRET=bootstrap/base/sealed-secrets-secret.yaml

OCP_VERSION=${OCP_VERSION}
TMP_DIR=generated


setup_bin() {
  mkdir -p ${TMP_DIR}/bin
  echo ${PATH} | grep -q "${TMP_DIR}/bin" || \
    export PATH=$(pwd)/${TMP_DIR}/bin:$PATH
}

check_ocp_install() {
  which openshift-install 2>&1 >/dev/null || download_ocp_install
  echo "auto-complete: . <(openshift-install completion bash)"
  . <(openshift-install completion bash)
  openshift-install version
  sleep 5
}

check_oc() {
  which oc 2>&1 >/dev/null || download_oc
  echo "auto-complete: . <(oc completion bash)"
  . <(oc completion bash)
  oc version
  sleep 5
}

check_kustomize() {
  which kustomize 2>&1 >/dev/null || download_kustomize
  echo "auto-complete: . <(kustomize completion bash)"
  . <(kustomize completion bash)
  kustomize version
  sleep 5
}

download_ocp_install() {
  DOWNLOAD_URL=https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable-${OCP_VERSION}/openshift-install-linux.tar.gz
  curl "${DOWNLOAD_URL}" -L | tar vzx -C ${TMP_DIR}/bin openshift-install
}

download_oc() {
  DOWNLOAD_URL=https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable-${OCP_VERSION}/openshift-client-linux.tar.gz
  curl "${DOWNLOAD_URL}" -L | tar vzx -C ${TMP_DIR}/bin oc
}

download_kustomize() {
  cd ${TMP_DIR}/bin
  curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash
  cd ../..
}


# check login
check_oc_login(){
  oc cluster-info | head -n1
  oc whoami || exit 1
  echo

  sleep 5
}

# create a sealed secret
create_sealed_secret(){
  read -r -p "Create NEW [${SEALED_SECRETS_SECRET}]? [y/N] " input
  case $input in
    [yY][eE][sS]|[yY])

      oc apply -k ${SEALED_SECRETS_FOLDER}
      [ -e ${SEALED_SECRETS_SECRET} ] && return

      # TODO: explore using openssl
      # oc -n sealed-secrets -o yaml \
      #   create secret generic

      # just wait for it
      sleep 20

      oc -n sealed-secrets -o yaml \
        get secret \
        -l sealedsecrets.bitnami.com/sealed-secrets-key=active \
        > ${SEALED_SECRETS_SECRET}
      ;;
    [nN][oO]|[nN]*)
      echo
      ;;
    *)
      echo
      ;;
  esac
}

# Validate sealed secrets secret exists
check_sealed_secret(){
  if [ -f ${SEALED_SECRETS_SECRET} ]; then
    echo "Exists: ${SEALED_SECRETS_SECRET}"
  else
    echo "Missing: ${SEALED_SECRETS_SECRET}"
    echo "The master key is required to bootstrap sealed secrets and CANNOT be checked into git."
    echo
    create_sealed_secret
  fi
}

install_gitops(){

  echo ""
  echo "Installing GitOps Operator."

  kustomize build components/operators/openshift-gitops/operator/overlays/stable/ | oc apply -f -

  echo "Pause ${SLEEP_SECONDS} seconds for the creation of the gitops-operator..."
  sleep ${SLEEP_SECONDS}

  echo "Waiting for operator to start"
  until oc get deployment gitops-operator-controller-manager -n openshift-operators
  do
    sleep 5;
  done

  echo "Waiting for openshift-gitops namespace to be created"
  until oc get ns ${ARGO_NS}
  do
    sleep 5;
  done

  echo "Waiting for deployments to start"
  until oc get deployment cluster -n ${ARGO_NS}
  do
    sleep 5;
  done

  echo "Waiting for all pods to be created"
  deployments=(cluster kam openshift-gitops-applicationset-controller openshift-gitops-redis openshift-gitops-repo-server openshift-gitops-server)
  for i in "${deployments[@]}";
  do
    echo "Waiting for deployment $i";
    oc rollout status deployment $i -n ${ARGO_NS}
  done
  
  echo ""
  echo "OpenShift GitOps successfully installed."

}

bootstrap_cluster(){
  echo "Apply overlay to override default instance"
  kustomize build ${bootstrap_dir} | oc apply -f -

  sleep 10
  echo "Waiting for all pods to redeploy"
  deployments=(cluster kam openshift-gitops-applicationset-controller openshift-gitops-redis openshift-gitops-repo-server openshift-gitops-server)
  for i in "${deployments[@]}";
  do
    echo "Waiting for deployment $i";
    oc rollout status deployment $i -n ${ARGO_NS}
  done

}

other(){
  PS3="Please select a bootstrap folder: "
  select bootstrap_dir in bootstrap/overlays/*/; 
  do
      test -n "$bootstrap_dir" && break;
      echo ">>> Invalid Selection";
  done

  echo "Selected: ${bootstrap_dir}"

  install_gitops

  bootstrap_cluster

  echo ""
  echo "GitOps has successfully deployed!  Check the status of the sync here:"

  route=$(oc get route openshift-gitops-server -o=jsonpath='{.spec.host}' -n ${ARGO_NS})

  echo "https://${route}"
}

setup_bin
check_oc
check_kustomize

check_oc_login
check_sealed_secret

other