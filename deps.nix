# generated by zon2nix (https://github.com/figsoda/zon2nix)

{ linkFarm, fetchzip }:

linkFarm "zig-packages" [
  {
    name = "12200301960bbde64052db068cf31a64091ce1f671898513d9b8d9e2be5b0e4b13a3";
    path = fetchzip {
      url = "https://github.com/zigzap/facil.io/archive/refs/tags/zap-0.0.12.tar.gz";
      hash = "sha256-dSlMecImqHjU9lenNsVSHdfMZWYHyIdNd3cuUCMY/rI=";
    };
  }
  {
    name = "1220a645e8ae84064f3342609f65d1c97e23c292616f5d1040cdf314ca52d7643f8a";
    path = fetchzip {
      url = "https://github.com/zigzap/zap/archive/refs/tags/v0.1.10-pre.tar.gz";
      hash = "sha256-L9ac2tWx8cJGVKo3sVUvxfcnPVHLGLihaieu92bi7kA=";
    };
  }
]
