<?php
return array(
    'ServerAddress' => getenv('FLUX_SERVER_ADDRESS') ?: 'ragnarok.feanor.com.br',
    'BaseURI' => '/',
    'ForceHTTPS' => true,
    'InstallerPassword' => getenv('FLUX_INSTALLER_PASSWORD'),
    'RequireOwnership' => true,
    'DefaultLanguage' => 'pt_br',
    'ThemeName' => array('bootstrap'),
);
