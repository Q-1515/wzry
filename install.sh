#!/bin/bash

# XXG-KAMI-PRO 一键安装脚本
# 作者: xiaoxiaoguai-yyds

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 检查是否为 root 用户
if [ "$EUID" -ne 0 ]; then 
  echo -e "${RED}请使用 root 权限运行此脚本${NC}"
  exit 1
fi

show_menu() {
    clear
    echo -e "${BLUE}================================================${NC}"
    echo -e "${BLUE}        XXG-KAMI-PRO 一键部署脚本 v1.0          ${NC}"
    echo -e "${BLUE}================================================${NC}"
    echo -e "欢迎使用小小怪卡密管理系统安装脚本！"
    echo -e "开源地址: https://github.com/xiaoxiaoguai-yyds/xxgkami-pro"
    echo -e "管理系统售后群: 1050160397"
    echo -e "${BLUE}================================================${NC}"
    echo -e "1. 安装系统 (全新安装)"
    echo -e "2. 更新系统 (保留数据更新)"
    echo -e "3. 更新本脚本"
    echo -e "4. 单独安装管理命令 (xxgkami)"
    echo -e "0. 退出"
    echo -e "${BLUE}================================================${NC}"
    read -p "请输入选项 [0-4]: " MENU_CHOICE
}

# 循环显示菜单，直到选择安装/更新或退出
while true; do
    show_menu
    case $MENU_CHOICE in
        1)
            echo -e "${GREEN}开始全新安装流程...${NC}"
            break # 跳出循环，继续执行后面的安装逻辑
            ;;
        2)
            echo -e "${GREEN}开始系统更新流程...${NC}"
            # 标记为更新模式，后续逻辑可据此跳过部分步骤（如数据库初始化）
            IS_UPDATE_MODE=true
            break # 跳出循环，继续执行后面的安装逻辑
            ;;
        3)
            echo -e "${YELLOW}正在更新脚本...${NC}"
            wget -O install.sh https://ghfast.top/https://raw.githubusercontent.com/xiaoxiaoguai-yyds/xxgkami-pro/refs/heads/master/install.sh && chmod +x install.sh
            echo -e "${GREEN}脚本更新完成，请重新运行 ./install.sh${NC}"
            exit 0
            ;;
        4)
            # 定义安装目录变量，因为后续生成脚本需要
            INSTALL_DIR="/var/www/xxgkami-pro"
            # 默认中国网络环境，如果需要检测可以在这里添加
            IS_CHINA=true 
            
            # 直接跳转到生成管理脚本的部分
            # 我们可以将管理脚本生成封装成函数，或者在这里直接写入
            # 为了简单起见，我们复制后面的生成逻辑，或者直接跳转
            # 但 Bash 不支持 GOTO，所以我们把生成逻辑封装成函数最好
            # 这里先临时定义一个变量来控制流程
            ONLY_INSTALL_CMD=true
            break
            ;;
        0)
            echo -e "${GREEN}感谢使用，再见！${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}无效选项，请重新输入${NC}"
            sleep 1
            ;;
    esac
done
