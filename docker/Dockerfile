FROM ruby:2.6.5

ARG AWS_DEFAULT_REGION
ARG AWS_ACCESS_KEY_ID 
ARG AWS_SECRET_ACCESS_KEY
ARG AWS_SESSION_TOKEN
ARG SSH_PUBLIC_KEY

WORKDIR /gifmachine

ADD gifmachine .
ADD docker/build_image.sh . 

RUN chmod +x build_image.sh
RUN ["/bin/bash","build_image.sh"]

CMD ruby app.rb -o 0.0.0.0