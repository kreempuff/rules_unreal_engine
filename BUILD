load("@io_bazel_rules_go//go:def.bzl", "go_binary", "go_library")
load("@bazel_gazelle//:def.bzl", "gazelle")
load(":rules_test.bzl", "unreal_target_test_suite")

# gazelle:prefix kreempuff.dev/rules-unreal-engine
gazelle(name = "gazelle")

gazelle(
    name = "gazelle-update-repos",
    args = [
        "-from_file=go.mod",
        "-to_macro=deps.bzl%go_dependencies",
        "-prune",
    ],
    command = "update-repos",
)

go_library(
    name = "rules-unreal-engine_lib",
    srcs = ["main.go"],
    importpath = "kreempuff.dev/rules-unreal-engine",
    visibility = ["//visibility:private"],
    deps = ["//cmd"],
)

go_binary(
    name = "rules-unreal-engine",
    embed = [":rules-unreal-engine_lib"],
    visibility = ["//visibility:public"],
)

unreal_target_test_suite(
    name = "unreal_target_test",
)

sh_binary(
    name = "Setup.sh",
    srcs = ["@unreal_engine//UnrealEngine:Setup.sh"],
    visibility = ["//visibility:public"],
)
