FROM alpine:latest

ARG PACKETVER
ARG SET_PRERENEWAL
ARG PACKET_OBFUSCATION_KEY1
ARG PACKET_OBFUSCATION_KEY2
ARG PACKET_OBFUSCATION_KEY3
ARG HOST

ENV PACKETVER=$PACKETVER
ENV SET_PRERENEWAL=$SET_PRERENEWAL
ENV PACKET_OBFUSCATION_KEY1=$PACKET_OBFUSCATION_KEY1
ENV PACKET_OBFUSCATION_KEY2=$PACKET_OBFUSCATION_KEY2
ENV PACKET_OBFUSCATION_KEY3=$PACKET_OBFUSCATION_KEY3
ENV HOST=$HOST

RUN apk update
RUN apk add --no-cache git
RUN apk add --no-cache apache2
RUN apk add --no-cache php$phpverx-apache2

RUN rm -r /var/www/localhost/htdocs
RUN echo "LoadModule rewrite_module modules/mod_rewrite.so" >> /etc/apache2/httpd.conf
RUN sed -i "s|AllowOverride None|AllowOverride All|g" /etc/apache2/httpd.conf

RUN git clone https://github.com/raiken-mf/roBrowserLegacy.git /var/www/localhost/htdocs
RUN git clone https://github.com/raiken-mf/roBrowserLegacy-RemoteClient-PHP.git /var/www/localhost/htdocs/client
RUN mkdir /var/www/localhost/htdocs/client/resources
RUN mkdir /var/www/localhost/htdocs/AI

RUN git clone -n --depth=1 --filter=tree:0 https://github.com/raiken-mf/ROenglishRE.git /opt/translation
RUN cd /opt/translation && \
    if [ -n "${SET_PRERENEWAL}" ] && [ "${SET_PRERENEWAL}" -ne 0 ]; then \
		git sparse-checkout set --no-cone Translation/Pre-Renewal && \
		git checkout && \
		cp -rs /opt/translation/Translation/Pre-Renewal/data/* /var/www/localhost/htdocs/client/data/ && \
		cp -rs /opt/translation/Translation/Pre-Renewal/System/* /var/www/localhost/htdocs/client/System/; \
    else \
		git sparse-checkout set --no-cone Translation/Renewal && \
		git checkout && \
		cp -rs /opt/translation/Translation/Renewal/data/* /var/www/localhost/htdocs/client/data/&& \
		cp -rs /opt/translation/Translation/Renewal/System/* /var/www/localhost/htdocs/client/System/; \
    fi

RUN rm -r /var/www/localhost/htdocs/client/resources && \
	rm -r /var/www/localhost/htdocs/client/BGM && \
	rm -r /var/www/localhost/htdocs/AI && \
	ln -s /opt/client_files/resources /var/www/localhost/htdocs/client/resources && \
	ln -s /opt/client_files/BGM /var/www/localhost/htdocs/client/BGM && \
	ln -s /opt/client_files/AI /var/www/localhost/htdocs/AI

RUN cat <<EOF > /var/www/localhost/htdocs/index.html
<!DOCTYPE html>
<html>
	<head>
		<title>ROBrowsers App from http://www.robrowser.com</title>
		<meta name="viewport" content="width=device-width, initial-scale=1, minimum-scale=1, maximum-scale=1, user-scalable=0, viewport-fit=cover">
		<script type="text/javascript" src="../api.js"></script>
		<script type="text/javascript">
			function initialize() {
				var ROConfig = {
					target:        document.getElementById("robrowser"),
					type:          ROBrowser.TYPE.FRAME,
					application:   ROBrowser.APP.ONLINE,
					remoteClient:  "http://${HOST}/client/",
					renewal:      	"${SET_PRERENEWAL}" == 0 ? false : true,
					width:          '100%',
					height:         '100%',
					development:    true,
					loadlua:		true,
					servers: [{
						display:     "Demo Server",
						desc:        "roBrowser's demo server",
						address:     "ragnarok_login",
						port:        6900,
						version:     25,
						langtype:    12,
						packetver:   ${PACKETVER},
						packetKeys:  [
							${PACKET_OBFUSCATION_KEY1},
							${PACKET_OBFUSCATION_KEY2},
							${PACKET_OBFUSCATION_KEY3},
						],
						socketProxy: "ws://${HOST}:5999/",
						//adminList:   [2000000]
					}],
					skipServerList:  true,
					skipIntro:       true,
				};
				var RO = new ROBrowser(ROConfig);
				RO.start();
			}
			window.addEventListener("load", initialize, false);
		</script>
		<style type="text/css">
			* { box-sizing: border-box; }
			body,
			#robrowser {
				min-height: 100vh;
				max-height: 100vh;
			}
			html,
			body {
				margin: 0;
				padding: 0;
			}
			iframe {
				width: 100%;
				height: 100vh;
				padding:0;
				display:block;
			}
		</style>
	</head>
	<body>
		<div id="robrowser">Initializing roBrowser...</div>
	</body>
</html>
EOF

COPY robrowser/repository_override /var/www/localhost/htdocs/

RUN apk del git

WORKDIR /var/www/localhost/htdocs

#RUN git clone https://github.com/MrAntares/roBrowserLegacy.git /opt/ragnarok_browser
#RUN svn checkout https://github.com/llchrisll/ROenglishRE/trunk/Renewal/data /var/www/localhost/htdocs/client/data
#RUN cd /opt/ragnarok_browser && git pr checkout https://github.com/wjrosa/Ragna.roBrowser/pull/3
