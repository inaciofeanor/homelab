<?php
$dbHost = getenv('DB_HOST') ?: 'rathena-db';
$dbPort = (int) (getenv('DB_PORT') ?: 3306);
$dbName = getenv('DB_NAME') ?: 'ragnarok';
$dbUser = getenv('DB_USER') ?: 'ragnarok';
$dbPass = getenv('DB_PASSWORD');

return array(
    array(
        'ServerName' => 'Feanor Ragnarok',
        'DbConfig' => array(
            'Hostname' => $dbHost, 'Port' => $dbPort, 'Username' => $dbUser,
            'Password' => $dbPass, 'Database' => $dbName, 'Persistent' => true,
        ),
        'LogsDbConfig' => array(
            'Hostname' => $dbHost, 'Port' => $dbPort, 'Username' => $dbUser,
            'Password' => $dbPass, 'Database' => $dbName, 'Persistent' => true,
        ),
        'WebDbConfig' => array(
            'Hostname' => $dbHost, 'Port' => $dbPort, 'Username' => $dbUser,
            'Password' => $dbPass, 'Database' => $dbName, 'Persistent' => true,
        ),
        'LoginServer' => array(
            'Address' => 'rathena', 'Port' => 6900, 'UseMD5' => false,
            'NoCase' => true, 'GroupID' => 0,
        ),
        'CharMapServers' => array(
            array(
                'ServerName' => 'Feanor Ragnarok', 'Renewal' => true,
                'MaxCharSlots' => 9,
                'ExpRates' => array('Base' => 100, 'Job' => 100, 'Mvp' => 100),
                'DropRates' => array(
                    'DropRateCap' => 9000,
                    'Common' => 100, 'CommonBoss' => 100, 'CommonMVP' => 100, 'CommonMin' => 1, 'CommonMax' => 10000,
                    'Heal' => 100, 'HealBoss' => 100, 'HealMVP' => 100, 'HealMin' => 1, 'HealMax' => 10000,
                    'Useable' => 100, 'UseableBoss' => 100, 'UseableMVP' => 100, 'UseableMin' => 1, 'UseableMax' => 10000,
                    'Equip' => 100, 'EquipBoss' => 100, 'EquipMVP' => 100, 'EquipMin' => 1, 'EquipMax' => 10000,
                    'Card' => 100, 'CardBoss' => 100, 'CardMVP' => 100, 'CardMin' => 1, 'CardMax' => 10000,
                    'MvpItem' => 100, 'MvpItemMin' => 1, 'MvpItemMax' => 10000, 'MvpItemMode' => 0,
                ),
                'CharServer' => array('Address' => 'rathena', 'Port' => 6121),
                'MapServer' => array('Address' => 'rathena', 'Port' => 5121),
            ),
        ),
    ),
);
