# run tests by building `neovim.tests`
{ vimUtils, writeText, neovim, vimPlugins
, neovimUtils, wrapNeovimUnstable
, neovim-unwrapped
, fetchFromGitLab
, runCommandLocal
, pkgs
}:
let
  inherit (neovimUtils) makeNeovimConfig;

  plugins = with vimPlugins; [
    {
      plugin = vim-obsession;
      config = ''
        map <Leader>$ <Cmd>Obsession<CR>
      '';
    }
  ];

  packagesWithSingleLineConfigs = with vimPlugins; [
    {
      plugin = vim-obsession;
      config = ''map <Leader>$ <Cmd>Obsession<CR>'';
    }
    {
      plugin = trouble-nvim;
      config = ''" placeholder config'';
    }
  ];

  nvimConfSingleLines = makeNeovimConfig {
    plugins = packagesWithSingleLineConfigs;
    customRC = ''
      " just a comment
    '';
  };

  nvimConfNix = makeNeovimConfig {
    inherit plugins;
    customRC = ''
      " just a comment
    '';
  };

  nvim-with-luasnip = wrapNeovim2 "-with-lua-packages" (makeNeovimConfig {
    plugins = [ {
        plugin = vimPlugins.luasnip;

      }
    ];
  });

  nvimAutoDisableWrap = makeNeovimConfig { };

  wrapNeovim2 = suffix: config:
    wrapNeovimUnstable neovim-unwrapped (config // {
      extraName = suffix;
    });

  nmt = fetchFromGitLab {
    owner = "rycee";
    repo = "nmt";
    rev = "d2cc8c1042b1c2511f68f40e2790a8c0e29eeb42";
    sha256 = "1ykcvyx82nhdq167kbnpgwkgjib8ii7c92y3427v986n2s5lsskc";
  };

  # neovim-drv must be a wrapped neovim
  runTest = neovim-drv: buildCommand:
    runCommandLocal "test-${neovim-drv.name}" ({
      nativeBuildInputs = [ ];
      meta.platforms = neovim-drv.meta.platforms;
    }) (''
      source ${nmt}/bash-lib/assertions.sh
      vimrc="${writeText "init.vim" neovim-drv.initRc}"
      luarc="${writeText "init.lua" neovim-drv.luaRcContent}"
      luarcGeneric="$out/patched.lua"
      vimrcGeneric="$out/patched.vim"
      mkdir $out
      ${pkgs.perl}/bin/perl -pe "s|\Q$NIX_STORE\E/[a-z0-9]{32}-|$NIX_STORE/eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee-|g" < "$vimrc" > "$vimrcGeneric"
      ${pkgs.perl}/bin/perl -pe "s|\Q$NIX_STORE\E/[a-z0-9]{32}-|$NIX_STORE/eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee-|g" < "$luarc" > "$luarcGeneric"
    '' + buildCommand);

in
  pkgs.recurseIntoAttrs (
rec {
  vim_empty_config = vimUtils.vimrcFile { beforePlugins = ""; customRC = ""; };

  ### neovim tests
  ##################
  nvim_with_plugins = wrapNeovim2 "-with-plugins" nvimConfNix;

  singlelinesconfig = runTest (wrapNeovim2 "-single-lines" nvimConfSingleLines) ''
      assertFileContains \
        "$luarcGeneric" \
        "vim.cmd.source \"/nix/store/eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee-init.vim"
      assertFileContent \
        "$vimrcGeneric" \
        "${./init-single-lines.vim}"
  '';

  nvim_via_override = neovim.override {
    extraName = "-via-override";
    configure = {
      packages.foo.start = [ vimPlugins.ale ];
      customRC = ''
        :help ale
      '';
    };
  };

  nvim_with_aliases = neovim.override {
    extraName = "-with-aliases";
    vimAlias = true;
    viAlias = true;
  };

  nvim_with_plug = neovim.override {
    extraName = "-with-plug";
    configure.packages.plugins = with pkgs.vimPlugins; {
      start = [
        (base16-vim.overrideAttrs(old: { pname = old.pname + "-unique-for-tests-please-dont-use"; }))
      ];
    };
    configure.customRC = ''
      color base16-tomorrow-night
      set background=dark
    '';
  };

  run_nvim_with_plug = runTest nvim_with_plug ''
    export HOME=$TMPDIR
    ${nvim_with_plug}/bin/nvim -V3log.txt -i NONE -c 'color base16-tomorrow-night'  +quit! -e
  '';

  nvim_with_ftplugin = let
    # this plugin checks that it's ftplugin/vim.tex is loaded before $VIMRUNTIME/ftplugin/vim.tex
    # $VIMRUNTIME/ftplugin/vim.tex sources $VIMRUNTIME/ftplugin/initex.vim which sets b:did_ftplugin
    # we save b:did_ftplugin's value in a `plugin_was_loaded_too_late` file
    texFtplugin = (pkgs.runCommandLocal "tex-ftplugin" {} ''
      mkdir -p $out/ftplugin
      echo 'call system("echo ". exists("b:did_ftplugin") . " > plugin_was_loaded_too_late")' >> $out/ftplugin/tex.vim
      echo ':q!' >> $out/ftplugin/tex.vim
    '') // { pname = "test-ftplugin"; };
    in

    neovim.override {
    extraName = "-with-ftplugin";
    configure.packages.plugins = {
      start = [
        texFtplugin
      ];
    };
  };

  # regression test that ftplugin files from plugins are loaded before the ftplugin
  # files from $VIMRUNTIME
  run_nvim_with_ftplugin = runTest nvim_with_ftplugin ''
    export HOME=$TMPDIR
    echo '\documentclass{article}' > main.tex

    ${nvim_with_ftplugin}/bin/nvim -i NONE -V3log.txt main.tex -c "set ft?" -c quit
    ls -l $TMPDIR
    # check the saved value b:did_ftplugin then our plugin has been loaded instead of neovim's
    result="$(cat plugin_was_loaded_too_late)"
    echo $result
    [ "$result" = 0 ]
  '';


  # check that the vim-doc hook correctly generates the tag
  # we know for a fact packer has a doc folder
  checkForTags = vimPlugins.packer-nvim.overrideAttrs(oldAttrs: {
    doInstallCheck = true;
    installCheckPhase = ''
      [ -f $out/doc/tags ]
    '';
  });

  # check that the vim-doc hook correctly generates the tag
  # for neovim packages from luaPackages
  # we know for a fact gitsigns-nvim has a doc folder and comes from luaPackages
  checkForTagsLuaPackages = vimPlugins.gitsigns-nvim.overrideAttrs(oldAttrs: {
    doInstallCheck = true;
    installCheckPhase = ''
      [ -f $out/doc/tags ]
    '';
  });

  nvim_with_gitsigns_plugin = neovim.override {
    extraName = "-with-gitsigns-plugin";
    configure.packages.plugins = {
      start = [
        vimPlugins.gitsigns-nvim
      ];
    };
  };
  checkHelpLuaPackages = runTest nvim_with_gitsigns_plugin ''
    export HOME=$TMPDIR
    ${nvim_with_gitsigns_plugin}/bin/nvim -i NONE -c 'help gitsigns' +quitall! -e
  '';

  # nixpkgs should detect that no wrapping is necessary
  nvimShouldntWrap = wrapNeovim2 "-should-not-wrap" nvimAutoDisableWrap;

  # this will generate a neovimRc content but we disable wrapping
  nvimDontWrap = wrapNeovim2 "-forced-nowrap" (makeNeovimConfig {
    wrapRc = false;
    customRC = ''
      " this shouldn't trigger the creation of an init.vim
    '';
  });

  force-nowrap = runTest nvimDontWrap ''
      ! grep -F -- ' -u' ${nvimDontWrap}/bin/nvim
  '';

  nvim_via_override-test = runTest nvim_via_override ''
      assertFileContent \
        "$vimrcGeneric" \
        "${./init-override.vim}"
  '';


  checkAliases = runTest nvim_with_aliases ''
      folder=${nvim_with_aliases}/bin
      assertFileExists "$folder/vi"
      assertFileExists "$folder/vim"
  '';

  # having no RC generated should autodisable init.vim wrapping
  nvim_autowrap = runTest nvim_via_override ''
      ! grep ${nvimShouldntWrap}/bin/nvim
  '';


  # system remote plugin manifest should be generated, deoplete should be usable
  # without the user having to do `UpdateRemotePlugins`. To test, launch neovim
  # and do `:call deoplete#enable()`. It will print an error if the remote
  # plugin is not registered.
  test_nvim_with_remote_plugin = neovim.override {
    extraName = "-remote";
    configure.packages.foo.start = with vimPlugins; [ deoplete-nvim ];
  };

  nvimWithLuaPackages = wrapNeovim2 "-with-lua-packages" (makeNeovimConfig {
    extraLuaPackages = ps: [ps.mpack];
    customRC = ''
      lua require("mpack")
    '';
  });

  nvim_with_lua_packages = runTest nvimWithLuaPackages ''
    export HOME=$TMPDIR
    ${nvimWithLuaPackages}/bin/nvim -i NONE --noplugin -es
  '';

  # nixpkgs should install optional packages in the opt folder
  nvim_with_opt_plugin = neovim.override {
    extraName = "-with-opt-plugin";
    configure.packages.opt-plugins = with pkgs.vimPlugins; {
      opt = [
        (dashboard-nvim.overrideAttrs(old: { pname = old.pname + "-unique-for-tests-please-dont-use-opt"; }))
      ];
    };
    configure.customRC = ''
      " Load all autoloaded plugins
      packloadall

      " Try to run Dashboard, and throw if it succeeds
      try
        Dashboard
        echo "Dashboard found, throwing error"
        cquit 1
      catch /^Vim\%((\a\+)\)\=:E492/
        echo "Dashboard not found"
      endtry

      " Load Dashboard as an optional
      packadd dashboard-nvim-unique-for-tests-please-dont-use-opt

      " Try to run Dashboard again, and throw if it fails
      let res = exists(':Dashboard')
      if res == 0
        echo "Dashboard not found, throwing error"
        cquit 1
      endif
      cquit 0
    '';
  };

  run_nvim_with_opt_plugin = runTest nvim_with_opt_plugin ''
    export HOME=$TMPDIR
    ${nvim_with_opt_plugin}/bin/nvim -i NONE +quit! -e
  '';

  inherit nvim-with-luasnip;

  # check that bringing in one plugin with lua deps makes those deps visible from wrapper
  # for instance luasnip has a dependency on jsregexp
  can_require_transitive_deps =
    runTest nvim-with-luasnip ''
    export HOME=$TMPDIR
    cat ${nvim-with-luasnip}/bin/nvim
    ${nvim-with-luasnip}/bin/nvim -i NONE --cmd "lua require'jsregexp'" -e +quitall!
  '';

})
