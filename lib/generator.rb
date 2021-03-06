# -*- coding: utf-8 -*-

#生成全站
require 'fileutils'

require_relative './scan'
require_relative './compiler'
require_relative './util'
require_relative './store'
require_relative './setup'

class Generator
    def initialize
        @util = Util.instance
        @setup = Setup.instance

        #删除目标目录
        FileUtils.rmtree @setup.target_dir

        #扫描文件
        scan = Scan.new
        scan.execute

        #存储文件
        @store = Store.new scan.files

        @compiler = Compiler.new
        @page_size = @setup.site_config['page_size'] || 10
        @page_size = 10 if @page_size.class != Integer

        self.generate_articles
        self.copy_theme_resource

        #复制文件
        self.copy_workbench_resource
        #生成首页
        self.generate_home
        #生成索引页
        self.generate_all_index @store.tree, '', true

        #如果需要执行命令命令
        self.execute_after_build
        puts 'Done...'
    end

    #build后执行的脚本
    def execute_after_build
        command = @setup.site_config['after_build_shell']
        return if not command
        exec command
    end
    #创建首页
    def generate_home
        children = @store.get_children(@store.tree)
        self.generate_index children, 1, 'home', ''
    end

    #创建所有的索引页, 如果有文件夹, 则根据配置创建文件夹中的索引页
    #不会创建首页的index
    def generate_all_index(node, dir, ignore_first_index)
        this = self

        #创建children的所有索引
        children = @store.get_children node
        page_count = (children.length.to_f / @page_size).ceil

        #生成此文件夹下的所有索引页
        (1..page_count).each { |page_index|
            #忽略第一页的索引, 一般是首页的情况下
            next if page_index == 1 and ignore_first_index

            # puts dir, page_index
            this.generate_index children, page_index, 'index', dir
        }

        #遍历所有的文件夹节点, 递归调用
        node.each { |key, sub_node|
            if not @store.is_children_key(key)
                parent_dir = dir + key + '/'
                this.generate_all_index sub_node, parent_dir, false
            end
        }
    end

    #创建所有文章页
    def generate_articles
        @store.articles.each { |key, article|
            relative_url = article['relative_url']

            data = {
                'article' => article
            }
            self.compiler(relative_url, 'article', data)
        }
    end

    #创建索引页, 包括首页以及子目录的索引页
    def generate_index(children, page_index, template_name, dir)
        articles = []
        start_index = page_index * @page_size - @page_size
        end_index = start_index + @page_size
        #总页数
        page_count = (children.length.to_f / @page_size).ceil

        path = dir + (page_index == 1 ? 'index.html' : "page-#{page_index}.html")

        children[start_index..end_index].each { |current|
            articles.push @store.articles[current]
        }



        data = {
            'articles' => articles,
            'nav' => self.get_nav(page_index, page_count)
        }

        self.compiler path, template_name, data
    end

    #处理上一页下一页
    def get_nav(page_index, page_count)
        nav = {}
        #上一页
        if(page_index == 2)
            nav['previous'] = 'index.html'
        elsif(page_index > 2)
            nav['previous'] = "page-#{page_index - 1}.html"
        end

        #下一页
        if(page_index < page_count)
            nav['next'] = "page-#{page_index + 1}.html"
        end

        #以后要处理总的分页信息

        nav
    end

    #编译模板
    def compiler(filename, template_name, data)
        data['categories'] = @store.categories
        data['product'] = @util.get_product 
        data['root/relative_path'] = @util.get_relative_dot(filename)

        @compiler.execute template_name, data, true, filename
    end

    #复制theme中的资源到目录
    def copy_theme_resource
        this = self
        theme_dir = @compiler.theme_dir

        Dir::entries(theme_dir).each{ |filename|
            #忽略掉以.开头的
            next if (/^\.|(template)/i =~ filename) != nil

            this.copy File::join(theme_dir, filename), filename
        }
    end

    #复制文件到目标
    def copy(source, filename)
        target = File::join @setup.target_dir, filename

        FileUtils.cp_r source, target
    end

    #复制工作目录的所有资源, 除忽略/.md/配置文件以外的
    def copy_workbench_resource
        this = self
        Dir::entries(@util.workbench).each{ |filename|
            #忽略掉以.开头的, 以及markdown文件, 还有用户忽略的文件
            next if @util.is_shadow_file?(filename) or
                @util.is_markdown_file?(filename) or
                @util.local_theme_dir == filename or
                @setup.is_user_ignore_file?(filename)

            #当前的路径
            current_path = @util.get_merge_path filename, @util.workbench

            #build和内容退出
            next if @setup.target_dir === current_path or
                @setup.content_dir === current_path or
                @util.is_config_file? current_path

            this.copy File::join(@util.workbench, filename), filename
        }
    end
end