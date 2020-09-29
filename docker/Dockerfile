FROM ruby:2.6.5

ARG AWS_DEFAULT_REGION
ARG AWS_ACCESS_KEY_ID 
ARG AWS_SECRET_ACCESS_KEY
ARG AWS_SESSION_TOKEN
ARG ENVIRONMENT
ARG COMPANY

WORKDIR /gifmachine

ADD gifmachine .
ADD docker/build_up.sh . 
ADD docker/start_up.sh . 

RUN chmod +x build_up.sh
RUN chmod +x start_up.sh
RUN ["/bin/bash","build_up.sh"]

CMD ["/bin/bash","start_up.sh"]