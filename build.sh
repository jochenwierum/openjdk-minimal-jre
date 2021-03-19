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
	checksum_musl="$3"
	name="$4"

	docker build \
		-t "$IMAGE:$name" \
		--build-arg "RELEASE=$release" \
		--build-arg "CHECKSUM=$checksum" \
		. \
		|| exit 2

	if [ -n "$checksum_musl" ]; then
		docker build -f Dockerfile.musl \
			-t "$IMAGE:$name-musl" \
			--build-arg "RELEASE=$release" \
			--build-arg "CHECKSUM=$checksum_musl" \
			. \
			|| exit 2
	fi
}

add_tags() {
	name="$1"
	tags="$2"
	checksum_musl="$3"

	[[ -z "$tags" ]] && return

	for tag in $tags; do
		echo " * $tag"
		docker tag "$IMAGE:$name" "$IMAGE:$tag"

		if [ -n "$checksum_musl" ]; then
			docker tag "$IMAGE:$name-musl" "$IMAGE:$tag-musl"
		fi
	done
}

push_images() {
	name="$1"
	tags="$2"
	checksum_musl="$3"

	for tag in "$name" $tags; do
		docker push "$IMAGE:$tag"
		if [ -n "$checksum_musl" ]; then
			docker push "$IMAGE:$tag-musl"
		fi
	done
}

build_new() {
	release="$1"
	checksum="$2"
	checksum_musl="$3"
	name="$4"
	tags="$5"

	echo "Building image"
	build_image "$release" "$checksum" "$checksum_musl" "$name"
	
	echo "Creating additional tags"
	add_tags "$name" "$tags" "$checksum_musl"
	
	echo "Publishing image"
	push_images "$name" "$tags" "$checksum_musl"
}

update_tag() {
	existing="$1"
	tag="$2"
	checksum_musl="$3"

	docker pull -q "$IMAGE:$existing"
	docker tag "$IMAGE:$existing" "$IMAGE:$tag"
	docker push "$IMAGE:$tag"

	if [ -n "$checksum_musl" ]; then
		docker pull -q "$IMAGE:$existing-musl"
		docker tag "$IMAGE:$existing-musl" "$IMAGE:$tag-musl"
		docker push "$IMAGE:$tag-musl"
	fi
}

update_tags() {
	existing="$1"
	name="$2"
	tags="$3"
	checksum_musl="$4"

	[[ -z "$tags" ]] && return

	for tag in $tags; do
		thash=$(find_on_hub "$tag")
		if [[ "$thash" != "$existing" ]]; then
			echo " * $tag"
			update_tag "$name" "$tag" "$checksum_musl"
		fi
	done
}

while IFS=, read -r release checksum checksum_musl name tags; do
	echo "=== $name ($release) ==="
	hash=$(find_on_hub $name)
	if [[ -z "$hash" ]]; then
		echo "Image does not exist yet - creating a new one"
		build_new "$release" "$checksum" "$checksum_musl" "$name" "$tags"
	else
		echo "Image already exists - verifying tags"
		update_tags "$hash" "$name" "$tags" "$checksum_musl"
	fi
	echo ""
done < versions.csv
