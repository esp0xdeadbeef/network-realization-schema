let
  escapeSegment = segment: builtins.replaceStrings [ "~" "/" ] [ "~0" "~1" ] (toString segment);

  joinPath =
    base: segment:
    if base == "" || base == "/" then
      "/${escapeSegment segment}"
    else
      "${base}/${escapeSegment segment}";

  leafRecords =
    {
      value,
      rootPath ? "",
    }:
    if builtins.isAttrs value then
      let
        names = builtins.attrNames value;
      in
      if names == [ ] then
        [
          {
            path = if rootPath == "" then "/" else rootPath;
            type = "attrs";
            value = { };
          }
        ]
      else
        builtins.concatLists (
          map (
            name:
            leafRecords {
              value = value.${name};
              rootPath = joinPath rootPath name;
            }
          ) names
        )
    else if builtins.isList value then
      if value == [ ] then
        [
          {
            path = if rootPath == "" then "/" else rootPath;
            type = "list";
            value = [ ];
          }
        ]
      else
        builtins.concatLists (
          builtins.genList (
            index:
            leafRecords {
              value = builtins.elemAt value index;
              rootPath = joinPath rootPath index;
            }
          ) (builtins.length value)
        )
    else
      [
        {
          path = if rootPath == "" then "/" else rootPath;
          type = builtins.typeOf value;
          inherit value;
        }
      ];

  pathsFor = args: map (record: record.path) (leafRecords args);
in
{
  inherit
    escapeSegment
    joinPath
    leafRecords
    pathsFor
    ;
}
