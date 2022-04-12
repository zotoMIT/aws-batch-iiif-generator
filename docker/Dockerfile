FROM ruby:2.7.5-bullseye
WORKDIR /usr/local/iiif
RUN apt-get update && apt-get install -y imagemagick awscli
RUN gem install --no-user-install --no-document iiif_s3
COPY policy.xml /etc/ImageMagick-6/policy.xml

COPY . .
CMD ["/usr/local/iiif/createiiif.sh"]
