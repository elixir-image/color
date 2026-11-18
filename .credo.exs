%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["lib/", "test/"],
        excluded: []
      },
      strict: true,
      color: true,
      checks: [
        # Module names like `Color.Mix`, `Color.ANSI`, `Color.Spectral` shadow
        # standard library modules when aliased; the library's public API uses
        # these names deliberately, so aliasing noise is not a defect here.
        {Credo.Check.Design.AliasUsage, false},
        # The library uses pattern-matched function heads liberally across
        # 21 colour-space structs and 16 blend modes; the default cyclomatic
        # threshold trips on genuinely linear dispatch tables. Individual
        # branchy functions carry inline `credo:disable` where needed.
        {Credo.Check.Refactor.CyclomaticComplexity, false},
        # Working-space and CSS parsing dispatch tables are naturally long;
        # splitting them obscures rather than clarifies.
        {Credo.Check.Refactor.Nesting, max_nesting: 3}
      ]
    }
  ]
}
