#!/usr/bin/env bash

set -e

OMADA_DIR="/opt/tplink/EAPController"
ARCH="${ARCH:-}"
OMADA_VER="${OMADA_VER:-}"
OMADA_TAR="${OMADA_TAR:-}"
OMADA_URL="https://static.tp-link.com/upload/beta/2024/202407/20240726/Omada_Controller_Linux_5.14.30.7_tar(Pre-release).zip"
OMADA_MAJOR_VER="$(echo "${OMADA_VER}" | awk -F '.' '{print $1}')"


# extract required data from the OMADA_URL
OMADA_TAR="$(echo "${OMADA_URL}" | awk -F '/' '{print $NF}')"
OMADA_VER="$(echo "${OMADA_TAR}" | awk -F '_v' '{print $2}' | awk -F '_' '{print $1}')"
OMADA_MAJOR_VER="${OMADA_VER%.*.*}"
OMADA_MAJOR_MINOR_VER="${OMADA_VER%.*}"


die() { echo -e "$@" 2>&1; exit 1; }

# common package dependencies
PKGS=(
  gosu
  unzip
  net-tools
  openjdk-17-jre-headless
  tzdata
  wget
  curl
  jq
)

case "${ARCH}" in
amd64|arm64|aarch64|"")
  PKGS+=( mongodb-server-core )
  ;;
*)
  die "${ARCH}: unsupported ARCH"
  ;;
esac

echo "ARCH=${ARCH}"
echo "OMADA_VER=${OMADA_VER}"
echo "OMADA_TAR=${OMADA_TAR}"
echo "OMADA_URL=${OMADA_URL}"

echo "**** Install Dependencies ****"
export DEBIAN_FRONTEND=noninteractive
apt-get update --fix-missing
apt-get install --no-install-recommends -y "${PKGS[@]}"

BASHIO_VERSION="0.16.2"
echo "**** Install BashIO ${BASHIO_VERSION}, for parsing HASS AddOn options ****"
mkdir -p /usr/src/bashio
curl -L -f -s "https://github.com/hassio-addons/bashio/archive/v${BASHIO_VERSION}.tar.gz" \
  | tar -xzf - --strip 1 -C /usr/src/bashio
mv /usr/src/bashio/lib /usr/lib/bashio
ln -s /usr/lib/bashio/bashio /usr/bin/bashio

echo "**** Download Omada Controller ****"
cd /tmp
wget -nv "${OMADA_URL}"


echo "**** Check if zip and extract ****"
if [[ $OMADA_TAR =~ \.zip$ ]]; then
	unzip "${OMADA_TAR}"
	cd "$(ls -t1 -d Omada*/ | head -n1)"
    echo "$(ls -t1 [Release]* | tail -n1)"
    OMADA_TAR="$(ls -t1 * | tail -n1)"
    echo "$OMADA_TAR"
else
	echo "File is not a zip"
fi


echo "**** Extract and Install Omada Controller ****"
tar zxvf "${OMADA_TAR}"
rm -f "${OMADA_TAR}"
cd Omada_SDN_Controller_*



# make sure tha the install directory exists
mkdir "${OMADA_DIR}" -vp

# starting with 5.0.x, the installation has no webapps directory; these values are pulled from the install.sh
NAMES=( bin properties lib install.sh uninstall.sh )


# copy over the files to the destination
for NAME in "${NAMES[@]}"
do
  cp "${NAME}" "${OMADA_DIR}" -r
done

# symlink to home assistant data dir
ln -s /data "${OMADA_DIR}"

# symlink for mongod
ln -sf "$(which mongod)" "${OMADA_DIR}/bin/mongod"
chmod 755 "${OMADA_DIR}"/bin/*

echo "${OMADA_VER}" > "${OMADA_DIR}/IMAGE_OMADA_VER.txt"

echo "**** Setup omada User Account ****"
groupadd -g 508 omada
useradd -u 508 -g 508 -d "${OMADA_DIR}" omada
chown -R omada:omada "${OMADA_DIR}/data"


echo "**** Cleanup ****"
rm -rf /tmp/* /var/lib/apt/lists/*
