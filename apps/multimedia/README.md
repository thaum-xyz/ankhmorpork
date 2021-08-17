## Caveats

### exportarr

For convenience exportarr is run as separate deployment and not as sidecar.
This way APIKEY can be generated in webUI before starting exportarr

### plex

traffic policy needs to be "Local" to prevent incorrect assumption of client source IP in plex 
