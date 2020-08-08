FROM ubuntu:latest AS jre

RUN apt-get -y update && apt-get -y upgrade && apt-get -y install curl binutils

ARG RELEASE
ARG CHECKSUM

RUN mkdir -p /tmp/jdk/ && \
    cd /tmp/jdk && \
	url="https://api.adoptopenjdk.net/v3/binary/version/$RELEASE/linux/x64/jdk/hotspot/normal/adoptopenjdk?project=jdk" && \
	echo "Downloading '$url' and expecting checksum $CHECKSUM" && \
	curl -s -L -o jdk.tgz "$url" && \
	echo "$CHECKSUM jdk.tgz" > SHA256SUMS && \
	sha256sum --status --strict -c SHA256SUMS

RUN for lib in libc6 zlib1g; do \
        listfile="/var/lib/dpkg/info/$lib.list"; \
        if [ ! -f "$listfile" ]; then \
            listfile="/var/lib/dpkg/info/$lib:amd64.list"; \
        fi; \
        [ -f "$listfile" ] || exit 1; \
        while IFS='' read -r file; do \
          if [ -f "$file" ]; then \
            dir="/target/$(dirname $file)"; \
            mkdir -p "$dir"; \
            cp -d --preserve=all "$file" "$dir"; \
          fi; \
        done < "$listfile"; \
      done; \
      rm -rf /target/usr/share/doc /target/usr/share/lintian; \
      mkdir -p /target/tmp /target/etc; \
      chmod 777 /target/tmp && chmod +t /target/tmp

RUN echo -e "root:x:0:\nnogroup:x:65534:\n" > /target/etc/group; \
    echo -e "root:x:0:0:root:/root:/bin/bash\nnobody:x:65534:65534:nobody:/nonexistent:/usr/sbin/nologin" > /target/etc/passwd

RUN tar -C /tmp/jdk --strip-components=1 -xzf /tmp/jdk/jdk.tgz && \
	/tmp/jdk/bin/jlink \
	--add-modules java.desktop \
	--add-modules java.sql \
	--add-modules java.naming \
	--add-modules jdk.unsupported \
	--add-modules java.management \
	--output /target/jre \
	--no-header-files \
	--no-man-pages \
	--strip-debug \
	--compress=2



FROM scratch

COPY --from=jre /target /

USER 65534
ENTRYPOINT [ "/jre/bin/java" ]
