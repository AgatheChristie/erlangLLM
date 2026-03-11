#!/bin/bash

set -e

# 获取当前时间
current_time=$(date '+%Y-%m-%d %H:%M:%S')

usage() {
    echo "用法: $0 [push [message...] | pull | status]"
    echo "  push [message...]  添加所有更改并提交推送，可选自定义提交信息"
    echo "  pull               从远程拉取"
    echo "  status             查看当前git状态"
}

cmd="$1"
shift || true

echo "当前时间: $current_time 正在执行命令: $cmd"

case "$cmd" in
  push)
    msg="$*"
    if [ -z "$msg" ]; then
      msg="现在的时间: $current_time"
    fi
    echo "正在添加所有文件..."
    git add .
    echo "正在提交更改..."
    if ! git commit -m "$msg"; then
      echo "没有需要提交的更改。"
    fi
    echo "正在推送到远程仓库..."
    git push
    echo "操作完成！"
    ;;
  pull)
    echo "正在从远程拉取..."
    git pull
    echo "拉取完成！"
    ;;
  status)
    git status
    ;;
  cc)
    explorer .
    ;;
  ""|-h|--help|help)
    usage
    ;;
  *)
    echo "未知命令: $cmd"
    usage
    exit 1
    ;;
esac
