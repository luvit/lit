FROM creationix/lit
ADD package.lua .
# There is a but in latest lit that segfaults while exiting only in docker build contexts
RUN lit install || true 
ADD main.lua .
EXPOSE 8080
CMD ["luvi", "."]