FROM ubuntu:xenial-20181113

MAINTAINER "René Moser" <mail@renemoser.net>

ARG src_url=https://github.com/apache/cloudstack/archive/4.13.1.0.tar.gz

RUN echo 'mysql-server mysql-server/root_password password root' | debconf-set-selections; \
    echo 'mysql-server mysql-server/root_password_again password root' | debconf-set-selections;

RUN apt-get -y update && apt-get dist-upgrade -y && apt-get install -y \
    genisoimage \
    libffi-dev \
    libssl-dev \
    sudo \
    ipmitool \
    maven \
    netcat \
    openjdk-8-jdk \
    python-dev \
    python-mysql.connector \
    python-pip \
    python-setuptools \
    python-paramiko \
    supervisor \
    wget \
    nginx \
    jq \
    mysql-server \
    openssh-client \
    && apt-get clean all \
    && rm -rf /var/lib/apt/lists/*;

# TODO: check if and why this is needed
RUN mkdir -p /root/.ssh \
    && chmod 0700 /root/.ssh \
    && ssh-keygen -t rsa -N "" -f id_rsa.cloud

RUN mkdir -p /var/run/mysqld; \
    chown mysql /var/run/mysqld; \
    echo '''sql_mode = "STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_AUTO_CREATE_USER,NO_ENGINE_SUBSTITUTION"''' >> /etc/mysql/mysql.conf.d/mysqld.cnf

RUN (/usr/bin/mysqld_safe &); sleep 5; mysqladmin -u root -proot password ''

RUN wget $src_url -O /opt/cloudstack.tar.gz; \
    mkdir -p /opt/cloudstack; \
    tar xvzf /opt/cloudstack.tar.gz -C /opt/cloudstack --strip-components=1

WORKDIR /opt/cloudstack

RUN mvn -Pdeveloper -Dsimulator -DskipTests clean install
RUN mvn -Pdeveloper -Dsimulator dependency:go-offline
RUN mvn -pl client jetty:run -Dsimulator -Djetty.skip -Dorg.eclipse.jetty.annotations.maxWait=120

RUN (/usr/bin/mysqld_safe &); \
    sleep 5; \
    mvn -Pdeveloper -pl developer -Ddeploydb; \
    mvn -Pdeveloper -pl developer -Ddeploydb-simulator; \
    MARVIN_FILE=$(find /opt/cloudstack/tools/marvin/dist/ -name "Marvin*.tar.gz"); \
    pip install --no-cache-dir setuptools-rust $MARVIN_FILE;

COPY zones.cfg /opt/zones.cfg
COPY nginx_default.conf /etc/nginx/sites-available/default
RUN pip install --no-cache-dir cs==2.5
COPY run.sh /opt/run.sh
COPY deploy.sh /opt/deploy.sh
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

RUN /opt/deploy.sh

EXPOSE 8888 8080 8096

CMD ["/usr/bin/supervisord"]
