-module(ai_json_util).



-compile(export_all).
-compile(nowarn_export_all).


%%====================================================================
%% JSON / 字符串 工具
%%====================================================================

%% @doc Binary-safe trim (不依赖 UTF-8 编码, 仅去除 ASCII 空白)
binary_trim(Bin) ->
    re:replace(Bin, <<"^\\s+|\\s+$">>, <<>>, [global, {return, binary}]).

%% @doc 从尾部截取不超过 MaxBytes 字节, 保证 UTF-8 字符完整
%%
%% 原来用 binary:part 按字节截断, 会把多字节汉字从中间劈开,
%% 产生无效 UTF-8 序列, 导致 jiffy:encode 报 invalid_string 错误。
%%
%% 修复: 截断后跳过开头的 UTF-8 续字节 (10xxxxxx), 对齐到合法字符边界。
truncate_utf8_tail(Bin, MaxBytes) when byte_size(Bin) =< MaxBytes ->
    Bin;
truncate_utf8_tail(Bin, MaxBytes) ->
    Start0 = byte_size(Bin) - MaxBytes,
    Start = align_utf8_start(Bin, Start0),
    binary:part(Bin, Start, byte_size(Bin) - Start).

%% 跳过 UTF-8 续字节 (10xxxxxx), 找到下一个字符的起始位置
align_utf8_start(_Bin, Pos) when Pos >= byte_size(_Bin) -> byte_size(_Bin);
align_utf8_start(Bin, Pos) ->
    case binary:at(Bin, Pos) of
        B when (B band 16#C0) =:= 16#80 ->  %% 续字节 10xxxxxx, 跳过
            align_utf8_start(Bin, Pos + 1);
        _ ->  %% ASCII 或多字节首字节, 这里是合法的截断点
            Pos
    end.

%% @doc 解析 AI 响应为 JSON Map
%% 组合: 提取 JSON 字符串 → 安全解析
%% 对应 aiEngine.ts 的 parseAIResponse()
parse_ai_response(Bin) when is_binary(Bin) ->
    case extract_json_from_response(Bin) of
        {ok, JsonBin}      -> safe_parse_json(JsonBin);
        {error, _} = Err   -> Err
    end.

%% @doc 从 AI 响应文本中提取 JSON 字符串
%% 对应 aiEngine.ts 的 extractJSONFromResponse()
%%
%% 多级回退策略:
%%   策略1: 提取 ```json ... ``` 代码块
%%   策略2: 检测是否直接以 { 或 [ 开头
%%   策略3: 查找第一个 { 或 [ 并截取
extract_json_from_response(Bin) when is_binary(Bin) ->
    Trimmed = binary_trim(Bin),
    case Trimmed of
        <<>> ->
            {error, empty_response};
        _ ->
            %% 策略1: 提取 ```json ... ``` 代码块
            case re:run(Trimmed, <<"```(?:json\\s*)?([\\s\\S]*?)```">>,
                [{capture, [1], binary}]) of
                {match, [CodeBlock]} ->
                    CB = binary_trim(CodeBlock),
                    case CB of
                        <<${, _/binary>> -> {ok, CB};
                        <<$[, _/binary>> -> {ok, CB};
                        _                -> try_direct_json(Trimmed)
                    end;
                nomatch ->
                    try_direct_json(Trimmed)
            end
    end.

%% 策略2: 直接以 { 或 [ 开头
try_direct_json(Bin) ->
    case Bin of
        <<${, _/binary>> -> {ok, Bin};
        <<$[, _/binary>> -> {ok, Bin};
        _                -> try_find_json(Bin)
    end.

%% 策略3: 查找第一个 { 或 [ 的位置并截取
try_find_json(Bin) ->
    BracePos   = binary:match(Bin, <<${>>),
    BracketPos = binary:match(Bin, <<$[>>),
    StartPos = case {BracePos, BracketPos} of
                   {nomatch, nomatch} -> nomatch;
                   {{P1, _}, nomatch} -> P1;
                   {nomatch, {P2, _}} -> P2;
                   {{P1, _}, {P2, _}} -> min(P1, P2)
               end,
    case StartPos of
        nomatch ->
            {error, no_json_found};
        Pos ->
            JsonPart = binary:part(Bin, Pos, byte_size(Bin) - Pos),
            {ok, JsonPart}
    end.

%% @doc 安全解析 JSON, 失败时尝试修复常见错误
%% 对应 aiEngine.ts 的 safeParseJSON()
safe_parse_json(Bin) when is_binary(Bin) ->
    try
        {ok, jiffy:decode(Bin, [return_maps])}
    catch _:_ ->
        repair_and_parse_json(Bin)
    end.

%% @doc 尝试修复常见 JSON 错误后重新解析
%% 对应 aiEngine.ts 的修复策略:
%%   1. 移除 UTF-8 BOM
%%   2. 移除尾部逗号 (,} 或 ,])
%%   3. 单引号 → 双引号
%%   4. 移除块注释 /* ... */
%%   5. 移除行注释 // ...
repair_and_parse_json(Bin) ->
    try
        B1 = remove_bom(Bin),
        B2 = re:replace(B1, <<",\\s*([}\\]])">>, <<"\\1">>,
            [global, {return, binary}]),
        B3 = binary:replace(B2, <<"'">>, <<"\"">>, [global]),
        B4 = re:replace(B3, <<"/\\*[\\s\\S]*?\\*/">>, <<>>,
            [global, {return, binary}]),
        B5 = re:replace(B4, <<"//[^\\n]*">>, <<>>,
            [global, {return, binary}]),
        {ok, jiffy:decode(B5, [return_maps])}
    catch _:RepairErr ->
        {error, {json_repair_failed, RepairErr}}
    end.


%% @doc 从部分 JSON buffer 中提取【根级别】"text" 字段的值
%%
%% AI 生成 JSON 字段的顺序不固定 (可能字母序, 也可能反序或 schema 序),
%% choices 里也有 "text" 字段, 必须跳过。
%% 通过追踪 JSON 嵌套深度, 只匹配深度 1 (根对象内) 的 "text" 键。
%%
%% 返回: {partial, DecodedText} | {complete, DecodedText} | not_found
extract_text_from_json(Buffer) ->
    case find_root_text_pos(Buffer) of
        {ok, AfterKey} ->
            case ai_json_util:skip_to_string_start(AfterKey) of
                {ok, StringContent} ->
                    ai_json_util:scan_json_string(StringContent, <<>>);
                not_found -> not_found
            end;
        not_found -> not_found
    end.

%% @private 扫描 JSON buffer, 追踪 {/}/[/] 深度, 找到根级别 "text" 键
find_root_text_pos(Buffer) ->
    scan_for_root_text(Buffer, 0, 0, false).

scan_for_root_text(Buffer, Pos, Depth, InStr) ->
    Size = byte_size(Buffer),
    if Pos >= Size -> not_found;
        true ->
            Ch = binary:at(Buffer, Pos),
            case InStr of
                true ->
                    case Ch of
                        $\\ -> scan_for_root_text(Buffer, min(Pos + 2, Size), Depth, true);
                        $"  -> scan_for_root_text(Buffer, Pos + 1, Depth, false);
                        _   -> scan_for_root_text(Buffer, Pos + 1, Depth, true)
                    end;
                false ->
                    case Ch of
                        ${ -> scan_for_root_text(Buffer, Pos + 1, Depth + 1, false);
                        $} -> scan_for_root_text(Buffer, Pos + 1, max(Depth - 1, 0), false);
                        $[ -> scan_for_root_text(Buffer, Pos + 1, Depth + 1, false);
                        $] -> scan_for_root_text(Buffer, Pos + 1, max(Depth - 1, 0), false);
                        $" when Depth =:= 1 ->
                            Remaining = Size - Pos,
                            case Remaining >= 6 andalso
                                binary:part(Buffer, Pos, 6) =:= <<"\"text\"">> of
                                true ->
                                    AfterText = Pos + 6,
                                    case next_non_ws(Buffer, AfterText) of
                                        $: ->
                                            {ok, binary:part(Buffer, AfterText, Size - AfterText)};
                                        _ ->
                                            scan_for_root_text(Buffer, AfterText, Depth, false)
                                    end;
                                false ->
                                    scan_for_root_text(Buffer, Pos + 1, Depth, true)
                            end;
                        $" ->
                            scan_for_root_text(Buffer, Pos + 1, Depth, true);
                        _ ->
                            scan_for_root_text(Buffer, Pos + 1, Depth, false)
                    end
            end
    end.

next_non_ws(Buffer, Pos) ->
    if Pos >= byte_size(Buffer) -> eof;
        true ->
            case binary:at(Buffer, Pos) of
                C when C =:= $\s; C =:= $\t; C =:= $\n; C =:= $\r ->
                    next_non_ws(Buffer, Pos + 1);
                Ch -> Ch
            end
    end.

%%====================================================================
%% 编码工具
%%====================================================================

%% 移除 UTF-8 BOM
remove_bom(<<16#EF, 16#BB, 16#BF, Rest/binary>>) -> Rest;
remove_bom(Bin) -> Bin.


%% 跳过冒号和空白, 找到字符串值的起始引号
skip_to_string_start(<<$\s, Rest/binary>>) -> skip_to_string_start(Rest);
skip_to_string_start(<<$\t, Rest/binary>>) -> skip_to_string_start(Rest);
skip_to_string_start(<<$\n, Rest/binary>>) -> skip_to_string_start(Rest);
skip_to_string_start(<<$\r, Rest/binary>>) -> skip_to_string_start(Rest);
skip_to_string_start(<<$:,  Rest/binary>>) -> skip_to_string_start(Rest);
skip_to_string_start(<<$",  Rest/binary>>) -> {ok, Rest};
skip_to_string_start(_) -> not_found.

%% @doc 扫描 JSON 字符串值, 正确处理转义字符
%% 返回: {partial, Decoded} | {complete, Decoded}
scan_json_string(<<>>, Acc)                          -> {partial, Acc};
scan_json_string(<<$\\>>, Acc)                       -> {partial, Acc};  %% 不完整转义, 等待更多数据
scan_json_string(<<$\\, $", R/binary>>, Acc)         -> scan_json_string(R, <<Acc/binary, $">>);
scan_json_string(<<$\\, $\\, R/binary>>, Acc)        -> scan_json_string(R, <<Acc/binary, $\\>>);
scan_json_string(<<$\\, $/, R/binary>>, Acc)         -> scan_json_string(R, <<Acc/binary, $/>>);
scan_json_string(<<$\\, $n, R/binary>>, Acc)         -> scan_json_string(R, <<Acc/binary, $\n>>);
scan_json_string(<<$\\, $r, R/binary>>, Acc)         -> scan_json_string(R, <<Acc/binary, $\r>>);
scan_json_string(<<$\\, $t, R/binary>>, Acc)         -> scan_json_string(R, <<Acc/binary, $\t>>);
scan_json_string(<<$\\, $b, R/binary>>, Acc)         -> scan_json_string(R, <<Acc/binary, $\b>>);
scan_json_string(<<$\\, $f, R/binary>>, Acc)         -> scan_json_string(R, <<Acc/binary, $\f>>);
scan_json_string(<<$\\, $u, Rest/binary>>, Acc) when byte_size(Rest) < 4 ->
    {partial, Acc};  %% 不完整 \uXXXX, 等待更多数据
scan_json_string(<<$\\, $u, Hex:4/binary, R/binary>>, Acc) ->
    try
        CP = binary_to_integer(Hex, 16),
        scan_json_string(R, <<Acc/binary, CP/utf8>>)
    catch _:_ ->
        scan_json_string(R, Acc)
    end;
scan_json_string(<<$\\, _, R/binary>>, Acc)          -> scan_json_string(R, Acc);  %% 未知转义, 跳过
scan_json_string(<<$", _/binary>>, Acc)              -> {complete, Acc};
scan_json_string(<<C, R/binary>>, Acc)               -> scan_json_string(R, <<Acc/binary, C>>).







