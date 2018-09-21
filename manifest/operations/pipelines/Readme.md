Info:

https://github.com/cloudfoundry-incubator/rfc5424
https://github.com/cloudfoundry/scalable-syslog


Snippets are in the folders, e.g. `cf-platform-es`, if you modify/add a snippet, 
in `cf-platform-es` you have to regenerate the operations file by running:


``` 
./generate_pipeline_operations.sh  cf-platform-es
```

Please commit the new generated `cf-platform-es.yml` and delete the old one.
