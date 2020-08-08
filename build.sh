#!/bin/bash

IMAGE=jochenwierum/openjdk-minimal-jre

find_on_hub() {
	tag="$1"
	
	token=$(curl --silent --location \
		"https://auth.docker.io/token?service=registry.docker.io&scope=repository:$IMAGE:pull" \
		| jq --raw-output .token)

	curl --silent --location \
		"https://registry.hub.docker.com/v2/$IMAGE/manifests/$tag" \
		-H "Authorization: Bearer $token" \
		-H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
		-o /dev/null \
		-D - \
		| awk -F: '/^Docker-Content-Digest/ {gsub(/ /,""); print $2":"$3}'
}

build_image() {
	release="$1"
	checksum="$2"
	name="$3"

	docker build \
		-t "$IMAGE:$name" \
		--build-arg "RELEASE=$release" \
		--build-arg "CHECKSUM=$checksum" \
		. \
		|| exit 2
}

add_tags() {
	name="$1"
	tags="$2"

	[[ -z "$tags" ]] && return

	for tag in $tags; do
		echo " * $tag"
		docker tag "$IMAGE:$name" "$IMAGE:$tag"
	done
}

push_images() {
	name="$1"
	tags="$2"

	for tag in "$name" $tags; do
		docker push "$IMAGE:$tag"
	done
}

build_new() {
	release="$1"
	checksum="$2"
	name="$3"
	tags="$4"

	echo "Building image"
	build_image "$release" "$checksum" "$name"
	
	echo "Creating additional tags"
	add_tags "$name" "$tags"
	
	echo "Publishing image"
	push_images "$name" "$tags"
}

update_tag() {
	existing="$1"
	tag="$2"

	docker pull -q "$IMAGE:$existing"
	docker tag "$IMAGE:$existing" "$IMAGE:$tag"
	docker push "$IMAGE:$tag"
}

update_tags() {
	existing="$1"
	name="$2"
	tags="$3"

	[[ -z "$tags" ]] && return

	for tag in $tags; do
		thash=$(find_on_hub "$tag")
		if [[ "$thash" != "$existing" ]]; then
			echo " * $tag"
			update_tag "$name" "$tag"
		fi
	done
}

while IFS=, read -r release checksum name tags; do
	echo "=== $name ($release) ==="
	hash=$(find_on_hub $name)
	echo $hash
	if [[ -z "$hash" ]]; then
		echo "Image does not exist yet - creating a new one"
		build_new "$release" "$checksum" "$name" "$tags"
	else
		echo "Image already exists - verifying tags"
		update_tags "$hash" "$name" "$tags"
	fi
	echo ""
done < versions.csv
