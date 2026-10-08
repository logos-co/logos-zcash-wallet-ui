{
  description = "Logos zcash_wallet_ui: the Zcash wallet app. Balances, receive, and wallet management; holds no key material.";

  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder";
    # Follows this builder: a skewed generated ABI crashes in provider init.
    zcash_wallet_backend = {
      url = "github:logos-co/logos-zcash-wallet-backend";
      inputs.logos-module-builder.follows = "logos-module-builder";
    };
  };

  outputs = inputs@{ logos-module-builder, ... }:
    logos-module-builder.lib.mkLogosQmlModule {
      src = ./.;
      configFile = ./metadata.json;
      flakeInputs = inputs;
    };
}
