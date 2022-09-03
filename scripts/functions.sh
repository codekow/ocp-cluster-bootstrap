#!/bin/bash
set -e

OCP_VERSION=4.10
TMP_DIR=generated

setup_bin(){
  mkdir -p ${TMP_DIR}/bin
  echo "${PATH}" | grep -q "${TMP_DIR}/bin" || \
    PATH=$(pwd)/${TMP_DIR}/bin:${PATH}
    export PATH
}

check_bin(){
  name=$1
  
  which "${name}" || download_"${name}"
 
  case ${name} in
    oc|openshift-install|kustomize)
      echo "auto-complete: . <(${name} completion bash)"
      
      # shellcheck source=/dev/null
      . <(${name} completion bash)
      
      ${name} version
      ;;
    *)
      echo
      ${name} --version
      ;;
  esac
  sleep 5
}

download_kubeseal(){
  DOWNLOAD_URL=https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.18.2/kubeseal-0.18.2-linux-amd64.tar.gz
  curl "${DOWNLOAD_URL}" -L | tar vzx -C ${TMP_DIR}/bin kubeseal
}


download_ocp-install(){
  DOWNLOAD_URL=https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable-${OCP_VERSION}/openshift-install-linux.tar.gz
  curl "${DOWNLOAD_URL}" -L | tar vzx -C ${TMP_DIR}/bin openshift-install
}

download_oc(){
  DOWNLOAD_URL=https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable-${OCP_VERSION}/openshift-client-linux.tar.gz
  curl "${DOWNLOAD_URL}" -L | tar vzx -C ${TMP_DIR}/bin oc
}

download_kustomize(){
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

