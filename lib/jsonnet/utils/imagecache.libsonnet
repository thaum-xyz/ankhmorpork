// 'images' are passed as a list of strings

{
    imagecache(metadata, images): {
        apiVersion: 'kubefledged.io/v1alpha2',
        kind: 'ImageCache',
        metadata: metadata,
        spec: {
            cacheSpec: [
                {
                    images: images,
                },
            ],
        },
    }
}
