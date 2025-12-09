FROM debian:latest

COPY init.sh /init.sh

CMD ["bash", "/init.sh"]
