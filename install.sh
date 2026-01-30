#!/bin/bash

# 王者荣耀雷达系统一键部署脚本 V2.0
# 适配系统：CentOS 7+/Debian 9+/Ubuntu 18.04+
# 核心功能：全新安装/更新/脚本自更/生成管理脚本/端口检测/多源适配

# ======================== 基础配置 ========================
# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # 重置颜色

# 全局变量
INSTALL_DIR="/www/wwwroot/wzry"  # 项目部署目录
JAR_FILE="home-server-0.0.1-SNAPSHOT.jar"
JAVA_PORT=8888  # Java服务端口
WEB_PORT=80     # Nginx端口
MYSQL_PORT=3306 # MySQL端口（可选）
IS_UPDATE_MODE=false  # 是否为更新模式
ONLY_INSTALL_CMD=false # 是否仅生成管理脚本
IS_CHINA=false        # 是否为国内网络环境
GIT_REPO=""           # 源码仓库地址
NGINX_IS_RUNNING=false # Nginx运行状态

# ======================== 菜单函数 ========================
show_menu() {
    clear
    echo -e "${PURPLE}================================================${NC}"
    echo -e "${PURPLE}          王者荣耀雷达系统一键部署工具          ${NC}"
    echo -e "${PURPLE}================================================${NC}"
    echo -e "${BLUE}[1] 全新安装（清空原有配置，重新部署）${NC}"
    echo -e "${BLUE}[2] 系统更新（保留配置，仅更新源码）${NC}"
    echo -e "${BLUE}[3] 更新部署脚本（自更新）${NC}"
    echo -e "${BLUE}[4] 生成快捷管理脚本（启动/停止/重启）${NC}"
    echo -e "${BLUE}[0] 退出${NC}"
    echo -e "${PURPLE}================================================${NC}"
    read -p "请选择操作（0-4）：" MENU_CHOICE
}

# ======================== 端口检测函数 ========================
check_port() {
    local port=$1
    local desc=$2
    local pid=""
    
    # 优先使用lsof，其次netstat/ss
    if command -v lsof >/dev/null 2>&1; then
        pid=$(lsof -t -i:$port)
    elif command -v netstat >/dev/null 2>&1; then
        pid=$(netstat -tulpn | grep ":$port " | awk '{print $7}' | cut -d '/' -f 1)
    elif command -v ss >/dev/null 2>&1; then
        pid=$(ss -lptn "sport = :$port" | grep -v State | awk '{print $6}' | cut -d',' -f2 | cut -d'=' -f2)
    fi

    if [ -n "$pid" ] && [ "$pid" != "-" ]; then
        echo -e "${YELLOW}⚠️  端口 $port ($desc) 已被占用 (PID: $pid)${NC}"
        read -p "是否终止占用进程？(y/n): " KILL_CHOICE
        if [ "$KILL_CHOICE" == "y" ] || [ "$KILL_CHOICE" == "Y" ]; then
            kill -9 $pid >/dev/null 2>&1
            sleep 1
            # 再次检测端口
            if lsof -t -i:$port >/dev/null 2>&1; then
                echo -e "${RED}❌ 进程 $pid 终止失败，请手动处理${NC}"
                return 1
            else
                echo -e "${GREEN}✅ 进程 $pid 已终止，端口 $port 释放成功${NC}"
            fi
        else
            echo -e "${YELLOW}ℹ️  保留占用进程，请确保端口无冲突${NC}"
            return 1
        fi
    else
        echo -e "${GREEN}✅ 端口 $port ($desc) 可用${NC}"
    fi
    return 0
}

# ======================== 网络检测函数 ========================
check_network() {
    echo -e "${YELLOW}[1/8] 检测网络环境...${NC}"
    # 检测是否为国内网络（访问谷歌失败则判定为国内）
    if curl -s --connect-timeout 5 https://www.google.com > /dev/null; then
        echo -e "${GREEN}📡 检测到国外网络环境，使用GitHub源${NC}"
        GIT_REPO="https://github.com/nmngl/wzry.git"
        JAR_URL="https://github.com/nmngl/wzry/raw/main/home-server-0.0.1-SNAPSHOT.jar"
        FRONT_URL="https://github.com/nmngl/wzry/archive/refs/heads/main.zip"
    else
        echo -e "${GREEN}📡 检测到国内网络环境，使用Gitee镜像源${NC}"
        IS_CHINA=true
        GIT_REPO="https://gitee.com/nmngl/wzry.git" # 需替换为实际Gitee镜像地址
        JAR_URL="https://gitee.com/nmngl/wzry/raw/main/home-server-0.0.1-SNAPSHOT.jar"
        FRONT_URL="https://gitee.com/nmngl/wzry/repository/archive/main.zip"
    fi
    echo -e "${BLUE}------------------------------------------------${NC}"
}

# ======================== 依赖检查/安装函数 ========================
# 检查Java版本（要求1.8）
check_java() {
    if java -version >/dev/null 2>&1; then
        JAVA_VER=$(java -version 2>&1 | head -n 1 | awk -F '"' '{print $2}' | awk -F '.' '{print $1$2}')
        # 1.8.x 会提取为 18，17.x 为17
        if [[ "$JAVA_VER" == "18" ]]; then
            echo -e "${GREEN}✅ Java 已安装 (版本: 1.8.x)${NC}"
            return 0
        else
            echo -e "${YELLOW}ℹ️  当前Java版本: $(java -version 2>&1 | head -n 1)，需要1.8.x${NC}"
        fi
    fi
    return 1
}

# 检查Nginx
check_nginx() {
    if nginx -V >/dev/null 2>&1; then
        echo -e "${GREEN}✅ Nginx 已安装${NC}"
        if systemctl is-active --quiet nginx; then
            echo -e "${GREEN}✅ Nginx 正在运行${NC}"
            NGINX_IS_RUNNING=true
        else
            NGINX_IS_RUNNING=false
            echo -e "${YELLOW}ℹ️  Nginx 已安装但未运行${NC}"
        fi
        return 0
    fi
    NGINX_IS_RUNNING=false
    return 1
}

# 检查PHP（要求8.2）
check_php() {
    if command -v php >/dev/null 2>&1; then
        PHP_VER=$(php -v | head -n 1 | awk -F ' ' '{print $2}' | awk -F '.' '{print $1$2}')
        if [[ "$PHP_VER" == "82" ]]; then
            echo -e "${GREEN}✅ PHP 已安装 (版本: 8.2.x)${NC}"
            return 0
        else
            echo -e "${YELLOW}ℹ️  当前PHP版本: $(php -v | head -n 1 | awk -F ' ' '{print $2}')，需要8.2.x${NC}"
        fi
    fi
    return 1
}

# 检查MySQL版本（可选，要求8.0+）
check_mysql_version() {
    echo -e "${YELLOW}[前置检查] 验证MySQL版本兼容性...${NC}"
    if ! command -v mysql >/dev/null 2>&1; then
        echo -e "${YELLOW}ℹ️  未检测到MySQL，跳过版本检查（可选依赖）${NC}"
        return 0
    fi
    
    local mysql_ver_str=$(mysql -V 2>&1)
    local mysql_ver=$(echo "$mysql_ver_str" | sed -n 's/.*Distrib \([0-9]\+\.[0-9]\+\).*/\1/p')
    if [ -z "$mysql_ver" ]; then
        mysql_ver=$(echo "$mysql_ver_str" | sed -n 's/.*Ver \([0-9]\+\.[0-9]\+\).*/\1/p')
    fi
    
    local required_ver="8.0"
    if [ -z "$mysql_ver" ]; then
         echo -e "${YELLOW}⚠️  无法识别MySQL版本，跳过检查${NC}"
         return 0
    fi

    echo -e "ℹ️  当前MySQL版本: ${mysql_ver}"
    echo -e "ℹ️  要求MySQL版本: ${required_ver}+"
    
    # 版本对比
    if awk "BEGIN {exit !($mysql_ver >= $required_ver)}"; then
        echo -e "${GREEN}✅ MySQL版本符合要求${NC}"
        return 0
    else
        echo -e "${RED}❌ MySQL版本不符合要求 (需要8.0+)${NC}"
        read -p "是否强制继续？(y/n): " FORCE_MYSQL
        if [ "$FORCE_MYSQL" != "y" ] && [ "$FORCE_MYSQL" != "Y" ]; then
            echo -e "${RED}❌ 安装已取消${NC}"
            exit 1
        fi
    fi
}

# 安装基础依赖（分系统）
install_deps() {
    echo -e "${YELLOW}[2/8] 安装基础依赖 (JDK1.8、PHP8.2、Nginx)...${NC}"
    # CentOS/RHEL
    if [ -f /etc/redhat-release ]; then
        # 安装EPEL源
        yum install -y epel-release >/dev/null 2>&1
        # 安装remi源（PHP8.2）
        yum install -y https://rpms.remirepo.net/enterprise/remi-release-7.rpm >/dev/null 2>&1
        # 安装基础工具
        yum install -y wget unzip git lsof net-tools >/dev/null 2>&1
        
        # 安装Java 1.8
        if ! check_java; then
            yum install -y java-1.8.0-openjdk-devel >/dev/null 2>&1
            echo -e "${GREEN}✅ JDK 1.8 安装完成${NC}"
        fi
        
        # 安装PHP8.2
        if ! check_php; then
            yum-config-manager --enable remi-php82 >/dev/null 2>&1
            yum install -y php82 php82-php-fpm php82-php-common >/dev/null 2>&1
            ln -sf /usr/bin/php82 /usr/bin/php >/dev/null 2>&1
            echo -e "${GREEN}✅ PHP 8.2 安装完成${NC}"
        fi
        
        # 安装Nginx
        if ! check_nginx; then
            yum install -y nginx >/dev/null 2>&1
            systemctl enable nginx >/dev/null 2>&1
            echo -e "${GREEN}✅ Nginx 安装完成${NC}"
        fi

    # Debian/Ubuntu
    elif [ -f /etc/debian_version ]; then
        apt update -y >/dev/null 2>&1
        apt install -y wget unzip git lsof net-tools apt-transport-https ca-certificates >/dev/null 2>&1
        
        # 安装Java 1.8
        if ! check_java; then
            apt install -y openjdk-8-jdk >/dev/null 2>&1
            echo -e "${GREEN}✅ JDK 1.8 安装完成${NC}"
        fi
        
        # 安装PHP8.2
        if ! check_php; then
            apt install -y software-properties-common >/dev/null 2>&1
            add-apt-repository -y ppa:ondrej/php >/dev/null 2>&1
            apt update -y >/dev/null 2>&1
            apt install -y php8.2 php8.2-fpm >/dev/null 2>&1
            echo -e "${GREEN}✅ PHP 8.2 安装完成${NC}"
        fi
        
        # 安装Nginx
        if ! check_nginx; then
            apt install -y nginx >/dev/null 2>&1
            systemctl enable nginx >/dev/null 2>&1
            echo -e "${GREEN}✅ Nginx 安装完成${NC}"
        fi
    else
        echo -e "${RED}❌ 不支持的操作系统${NC}"
        exit 1
    fi

    # 验证依赖
    if ! command -v java &> /dev/null || ! command -v nginx &> /dev/null || ! command -v php &> /dev/null; then
        echo -e "${RED}❌ 核心依赖安装失败，请手动检查${NC}"
        exit 1
    fi
    echo -e "${GREEN}✅ 基础依赖安装完成${NC}"
    echo -e "${BLUE}------------------------------------------------${NC}"
}

# ======================== 部署核心逻辑 ========================
# 下载/更新源码
download_source() {
    echo -e "${YELLOW}[3/8] 下载/更新项目源码...${NC}"
    # 创建目录
    mkdir -p $INSTALL_DIR
    cd $INSTALL_DIR || exit 1

    # 更新模式：保留配置，仅覆盖源码
    if [ "$IS_UPDATE_MODE" = true ]; then
        echo -e "${YELLOW}ℹ️  更新模式：保留配置文件，仅更新核心源码${NC}"
        # 备份配置文件（示例）
        cp -f $INSTALL_DIR/application.yml $INSTALL_DIR/application.yml.bak >/dev/null 2>&1
    fi

    # 下载前端源码
    wget -O wzry-main.zip $FRONT_URL --no-check-certificate -q
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ 前端源码下载失败${NC}"
        exit 1
    fi
    unzip -o wzry-main.zip -d $INSTALL_DIR >/dev/null 2>&1
    mv $INSTALL_DIR/wzry-main/* $INSTALL_DIR/ >/dev/null 2>&1
    rm -rf wzry-main.zip wzry-main

    # 下载Java JAR包
    wget -O $INSTALL_DIR/$JAR_FILE $JAR_URL --no-check-certificate -q
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ JAR包下载失败${NC}"
        exit 1
    fi
    chmod +x $INSTALL_DIR/$JAR_FILE

    # 更新模式：恢复配置文件
    if [ "$IS_UPDATE_MODE" = true ] && [ -f "$INSTALL_DIR/application.yml.bak" ]; then
        mv -f $INSTALL_DIR/application.yml.bak $INSTALL_DIR/application.yml >/dev/null 2>&1
        echo -e "${GREEN}✅ 配置文件已恢复${NC}"
    fi

    echo -e "${GREEN}✅ 源码下载/更新完成${NC}"
    echo -e "${BLUE}------------------------------------------------${NC}"
}

# 配置Nginx
config_nginx() {
    echo -e "${YELLOW}[4/8] 配置Nginx反向代理...${NC}"
    NGINX_CONF="/etc/nginx/conf.d/wzry.conf"
    # 备份原有配置
    cp -f $NGINX_CONF $NGINX_CONF.bak >/dev/null 2>&1

    # 写入新配置
    cat > $NGINX_CONF << EOF
server {
    listen $WEB_PORT;
    server_name _;
    root $INSTALL_DIR;
    index index.html index.php;

    # PHP配置
    location ~ \.php$ {
        fastcgi_pass unix:/run/php/php8.2-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    # 静态资源缓存
    location ~* \.(js|css|png|jpg|jpeg|gif|ico)$ {
        expires 30d;
        add_header Cache-Control "public, max-age=2592000";
    }

    # 反向代理Java服务
    location /api {
        proxy_pass http://127.0.0.1:$JAVA_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
EOF

    # 检查配置并重启
    if nginx -t >/dev/null 2>&1; then
        systemctl restart nginx >/dev/null 2>&1
        echo -e "${GREEN}✅ Nginx配置完成并重启${NC}"
    else
        echo -e "${RED}❌ Nginx配置错误，恢复备份配置${NC}"
        mv -f $NGINX_CONF.bak $NGINX_CONF >/dev/null 2>&1
        systemctl restart nginx >/dev/null 2>&1
        exit 1
    fi
    echo -e "${BLUE}------------------------------------------------${NC}"
}

# 启动Java服务
start_java_service() {
    echo -e "${YELLOW}[5/8] 启动Java后端服务...${NC}"
    # 停止原有服务
    ps -ef | grep $JAR_FILE | grep -v grep | awk '{print $2}' | xargs kill -9 >/dev/null 2>&1
    sleep 1

    # 后台启动（指定内存）
    nohup java -jar -Xmx1024M -Xms256M $INSTALL_DIR/$JAR_FILE > $INSTALL_DIR/wzry.log 2>&1 &
    sleep 3

    # 检查启动状态
    if netstat -tulpn | grep -q ":$JAVA_PORT "; then
        echo -e "${GREEN}✅ Java服务启动成功 (端口: $JAVA_PORT)${NC}"
    else
        echo -e "${RED}❌ Java服务启动失败，日志路径: $INSTALL_DIR/wzry.log${NC}"
        exit 1
    fi
    echo -e "${BLUE}------------------------------------------------${NC}"
}

# 生成快捷管理脚本
generate_manage_script() {
    echo -e "${YELLOW}[6/8] 生成快捷管理脚本...${NC}"
    MANAGE_SCRIPT="$INSTALL_DIR/wzry_manage.sh"
    cat > $MANAGE_SCRIPT << EOF
#!/bin/bash
# 王者荣耀雷达系统管理脚本
JAR_FILE="$INSTALL_DIR/$JAR_FILE"
JAVA_PORT=$JAVA_PORT

case \$1 in
    start)
        ps -ef | grep \$JAR_FILE | grep -v grep | awk '{print \$2}' | xargs kill -9 >/dev/null 2>&1
        nohup java -jar -Xmx1024M -Xms256M \$JAR_FILE > $INSTALL_DIR/wzry.log 2>&1 &
        echo "✅ 服务启动中，请等待3秒..."
        sleep 3
        if netstat -tulpn | grep -q ":\$JAVA_PORT "; then
            echo "✅ 服务启动成功"
        else
            echo "❌ 服务启动失败"
        fi
        ;;
    stop)
        ps -ef | grep \$JAR_FILE | grep -v grep | awk '{print \$2}' | xargs kill -9 >/dev/null 2>&1
        echo "✅ 服务已停止"
        ;;
    restart)
        \$0 stop
        sleep 2
        \$0 start
        ;;
    status)
        if netstat -tulpn | grep -q ":\$JAVA_PORT "; then
            echo "✅ 服务运行中 (端口: \$JAVA_PORT)"
        else
            echo "❌ 服务已停止"
        fi
        ;;
    log)
        tail -f $INSTALL_DIR/wzry.log
        ;;
    *)
        echo "使用方法: \$0 [start|stop|restart|status|log]"
        ;;
esac
EOF
    chmod +x $MANAGE_SCRIPT
    echo -e "${GREEN}✅ 管理脚本生成完成: $MANAGE_SCRIPT${NC}"
    echo -e "${YELLOW}ℹ️  使用方法: ./wzry_manage.sh [start|stop|restart|status|log]${NC}"
    echo -e "${BLUE}------------------------------------------------${NC}"
}

# ======================== 主流程 ========================
main() {
    # 检查root权限
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}❌ 请使用root权限运行（sudo ./install.sh）${NC}"
        exit 1
    fi

    # 循环显示菜单
    while true; do
        show_menu
        case $MENU_CHOICE in
            1)
                echo -e "${GREEN}🚀 开始全新安装流程...${NC}"
                sleep 1
                break
                ;;
            2)
                echo -e "${GREEN}🔄 开始系统更新流程...${NC}"
                IS_UPDATE_MODE=true
                sleep 1
                break
                ;;
            3)
                echo -e "${YELLOW}📥 正在更新脚本...${NC}"
                # 替换为实际脚本地址
                wget -O install.sh https://ghfast.top/https://raw.githubusercontent.com/nmngl/wzry/main/install.sh --no-check-certificate -q && chmod +x install.sh
                if [ $? -eq 0 ]; then
                    echo -e "${GREEN}✅ 脚本更新完成，请重新运行 ./install.sh${NC}"
                else
                    echo -e "${RED}❌ 脚本更新失败${NC}"
                fi
                exit 0
                ;;
            4)
                echo -e "${GREEN}📝 生成快捷管理脚本...${NC}"
                ONLY_INSTALL_CMD=true
                break
                ;;
            0)
                echo -e "${GREEN}👋 感谢使用，再见！${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}❌ 无效选项，请重新输入${NC}"
                sleep 1
                ;;
        esac
    done

    # 仅生成管理脚本
    if [ "$ONLY_INSTALL_CMD" = true ]; then
        generate_manage_script
        exit 0
    fi

    # 0.5 端口检测
    echo -e "${YELLOW}[0.5/8] 检测端口占用...${NC}"
    check_port $WEB_PORT "Nginx Web"
    check_port $JAVA_PORT "Java Backend"
    check_port $MYSQL_PORT "MySQL Database"
    # 防火墙提示
    echo -e "${RED}⚠️  重要提示: 请确保服务器防火墙/安全组已开放以下端口:${NC}"
    echo -e "${GREEN}  - $WEB_PORT (TCP) : 网站访问${NC}"
    echo -e "${GREEN}  - $JAVA_PORT (TCP) : 后端API服务${NC}"
    echo -e "${GREEN}  - $MYSQL_PORT (TCP) : (可选) 数据库访问${NC}"
    echo -e "${BLUE}------------------------------------------------${NC}"
    sleep 3

    # 1. 网络检测
    check_network

    # 2. 安装依赖
    install_deps

    # 3. 检查MySQL版本（可选）
    check_mysql_version

    # 4. 下载源码
    download_source

    # 5. 配置Nginx
    config_nginx

    # 6. 启动Java服务
    start_java_service

    # 7. 生成管理脚本
    generate_manage_script

    # 部署完成
    clear
    echo -e "${GREEN}================================================${NC}"
    echo -e "${GREEN}          部署完成！🎉${NC}"
    echo -e "${GREEN}================================================${NC}"
    echo -e "📁 项目目录：$INSTALL_DIR"
    echo -e "🌐 访问地址：http://你的服务器IP:$WEB_PORT"
    echo -e "🔧 Java端口：$JAVA_PORT"
    echo -e "📜 日志文件：$INSTALL_DIR/wzry.log"
    echo -e "⚙️  管理脚本：$INSTALL_DIR/wzry_manage.sh"
    echo -e "${GREEN}================================================${NC}"
}

# 执行主函数
main
