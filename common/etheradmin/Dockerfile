FROM node:8.11.1

# Create app directory
WORKDIR /usr/src/app

ENV listenPort ""
ENV consortiumId ""
ENV azureStorageAccount ""
ENV azureStorageAccessKey ""
ENV containerName ""
ENV identityBlobPrefix ""
ENV ethRpcPort ""
ENV validatorListBlobName ""
ENV paritySpecBlobName ""
ENV valSetContractBlobName ""
ENV adminContractBlobName ""
ENV adminContractABIBlobName ""
ENV adminSiteLogFile ""
ENV storageDnsSuffix ""
ENV storageApiVersion ""
ENV userCert ""
ENV NODE_EXTRA_CA_CERTS ${userCert}
ENV AZURE_STORAGE_DNS_SUFFIX ${storageDnsSuffix}

# Install app dependencies
# A wildcard is used to ensure both package.json AND package-lock.json are copied
# where available (npm@5+)
COPY package*.json ./

COPY public ./
COPY assets ./
COPY views ./

# Update package utility
RUN apt-get -y update
RUN apt-get -y install npm

# Install node storage package that accepts API version as configurable value
RUN npm install git+https://github.com/seyadava/azure-storage-node.git

RUN npm install -g

RUN export NODE_EXTRA_CA_CERTS=${userCert}
RUN export AZURE_STORAGE_DNS_SUFFIX=${storageDnsSuffix}

# Bundle app source
COPY . .

CMD ["sh", "-c", "node etheradmin.js ${listenPort} ${consortiumId} ${azureStorageAccount} ${azureStorageAccessKey} ${containerName} ${identityBlobPrefix} ${ethRpcPort} ${validatorListBlobName} ${paritySpecBlobName} ${valSetContractBlobName} ${adminContractBlobName} ${adminContractABIBlobName} ${adminSiteLogFile} ${storageDnsSuffix} ${storageApiVersion} ${userCert}"]