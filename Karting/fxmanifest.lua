fx_version 'cerulean'
game 'gta5'

author 'Abel'
description 'Gokart Rental System'
version '1.0.0'

shared_script {
    '@es_extended/imports.lua',
    'config.lua'
}

server_scripts {
    '@es_extended/locale.lua',
    '@mysql-async/lib/MySQL.lua',
    'config.lua',
    'server.lua'
}

client_scripts {
    '@es_extended/locale.lua',
    'config.lua',
    'client.lua'
}

ui_page 'ui/index.html'

files {
    'ui/index.html',
    'ui/style.css',
    'ui/script.js'
} 