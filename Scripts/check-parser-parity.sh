#!/usr/bin/env bash
set -euo pipefail

# 校验 SkillportPreview extension 里的 SKILLMdParser 和主 app 的 parse 函数体保持一致。
# 允许的差异：error 类型签名 (file:URL? 参数)、注释、import、空行。

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
main_parser="$repo_root/Domain/Parsers/SKILLMdParser.swift"
ext_parser="$repo_root/SkillportPreview/SKILLMdParser.swift"

if [ ! -f "$main_parser" ] || [ ! -f "$ext_parser" ]; then
    echo "❌ missing parser file"
    echo "  expected: $main_parser"
    echo "  expected: $ext_parser"
    exit 1
fi

# Normalize: 删除注释 / 空行 / import / 把 parseFailed(file: nil, reason:) 归一化为 parseFailed(reason:)
normalize() {
    sed -E '
        s/SkillportError\.parseFailed\(file: nil, reason:/SkillportError.parseFailed(reason:/g;
        /^[[:space:]]*\/\//d;
        /^[[:space:]]*$/d;
        /^import /d;
    '
}

# 只比 parse(_ raw:) 函数体 — serialize 不在 extension 里
extract_parse_body() {
    awk '/public static func parse\(/,/^    \}$/' "$1"
}

main_norm=$(extract_parse_body "$main_parser" | normalize)
ext_norm=$(extract_parse_body "$ext_parser" | normalize)

if ! diff -u <(echo "$main_norm") <(echo "$ext_norm") > /tmp/parser-diff.txt; then
    echo "❌ SKILLMdParser.parse drift detected between main app and SkillportPreview"
    echo "   Re-sync SkillportPreview/SKILLMdParser.swift with Domain/Parsers/SKILLMdParser.swift"
    echo "   Diff:"
    cat /tmp/parser-diff.txt
    exit 1
fi

echo "✅ SKILLMdParser parity OK"
