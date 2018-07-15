FROM ocaml/opam2:alpine
WORKDIR ezpostgresql
ENV OPAMYES true
ADD ezpostgresql.opam .
RUN sudo apk update && \
    opam pin add -yn ezpostgresql . && \
    opam install depext && \
    opam depext ezpostgresql && \
    opam install --deps-only --build-test ezpostgresql && \
    sudo rm -rf /var/cache/apk/*
ADD . .
RUN sudo chown -R opam:nogroup .
CMD opam config exec dune runtest
