#!/usr/bin/perl

use strict;
use warnings;
use lib 't/lib';

use English qw(-no_match_vars);
use Test::Deep;
use Test::Exception;
use Test::More;
use Cpanel::JSON::XS;

use GLPI::Agent::Logger;
use GLPI::Agent::Version;
use GLPI::Agent::XML::Response;

use GLPI::Agent::Protocol::Inventory;

my $deviceid = "device-id-123456789";
my %inventories = (
    # each case: case_name => {
    #   content  => { INVENTORY HASH as generated by Inventory task },
    #   expected => { resulting hash after being normalized and json decoded },
    #   itemtype => "Computer"
    # }
    "simple" => {
        content     => {
            BIOS    => {
                BDATE   => "2021-06-25",
            }
        },
        expected    => {
            action      => "inventory",
            deviceid    => $deviceid,
            itemtype    => "Computer",
            content     => {
                bios    => {
                    bdate   => "2021-06-25",
                }
            }
        },
        itemtype    => "Computer",
    },
    "bdate fix" => {
        content     => {
            BIOS    => {
                BDATE   => "25/06/2021",
            }
        },
        expected    => {
            action      => "inventory",
            deviceid    => $deviceid,
            itemtype    => "Computer",
            content     => {
                bios    => {
                    bdate   => "2021-06-25",
                }
            }
        },
        itemtype    => "Computer",
    },
    "bdate fix with assettag cleanup" => {
        content     => {
            BIOS    => {
                BDATE   => "25/06/2021",
                ASSETTAG => undef
            }
        },
        expected    => {
            action      => "inventory",
            deviceid    => $deviceid,
            itemtype    => "Computer",
            content     => {
                bios    => {
                    bdate   => "2021-06-25",
                }
            }
        },
        itemtype    => "Computer",
    },
    "antivirus boolean" => {
        content     => {
            ANTIVIRUS   => {
                ENABLED => "1",
            }
        },
        expected    => {
            action      => "inventory",
            deviceid    => $deviceid,
            itemtype    => "Computer",
            content     => {
                antivirus   => {
                    enabled => $Cpanel::JSON::XS::true,
                }
            }
        },
        itemtype    => "Computer",
    },
    "antivirus boolean with fixed expiration" => {
        content     => {
            ANTIVIRUS   => {
                ENABLED     => "1",
                EXPIRATION  => "2021-06-25 17:12:33",
            }
        },
        expected    => {
            action      => "inventory",
            deviceid    => $deviceid,
            itemtype    => "Computer",
            content     => {
                antivirus   => {
                    enabled     => $Cpanel::JSON::XS::true,
                    expiration  => "2021-06-25",
                }
            }
        },
        itemtype    => "Computer",
    },
    "antivirus boolean with fixed expiration (2)" => {
        content     => {
            ANTIVIRUS   => {
                ENABLED     => 0,
                EXPIRATION  => "25/06/2021",
            }
        },
        expected    => {
            action      => "inventory",
            deviceid    => $deviceid,
            itemtype    => "Computer",
            content     => {
                antivirus   => {
                    enabled     => $Cpanel::JSON::XS::false,
                    expiration  => "2021-06-25",
                }
            }
        },
        itemtype    => "Computer",
    },
    "antivirus boolean and wrong expiration" => {
        content     => {
            ANTIVIRUS   => {
                ENABLED     => "1",
                EXPIRATION  => "never",
            }
        },
        expected    => {
            action      => "inventory",
            deviceid    => $deviceid,
            itemtype    => "Computer",
            content     => {
                antivirus   => {
                    enabled     => $Cpanel::JSON::XS::true,
                }
            }
        },
        itemtype    => "Computer",
    },
    "process" => {
        content     => {
            PROCESSES   => {
                CMD     => "init",
                STARTED => "2021-12-10 00:00",
                PID     => "001",
                USER    => "root",
            }
        },
        expected    => {
            action      => "inventory",
            deviceid    => $deviceid,
            itemtype    => "Computer",
            content     => {
                processes   => {
                    cmd     => "init",
                    started => "2021-12-10 00:00:00",
                    pid     => 1,
                    user    => "root"
                }
            }
        },
        itemtype    => "Computer",
    },
    "process with date" => {
        content     => {
            PROCESSES   => {
                CMD     => "init",
                STARTED => "25/06/2021",
                PID     => "001",
                USER    => "root",
            }
        },
        expected    => {
            action      => "inventory",
            deviceid    => $deviceid,
            itemtype    => "Computer",
            content     => {
                processes   => {
                    cmd     => "init",
                    started => "2021-06-25 00:00:00",
                    pid     => 1,
                    user    => "root"
                }
            }
        },
        itemtype    => "Computer",
    },
    "process and wrong dateordatetime" => {
        content     => {
            PROCESSES   => {
                CMD     => "init",
                STARTED => "at boot",
                PID     => "001",
                USER    => "root",
            }
        },
        expected    => {
            action      => "inventory",
            deviceid    => $deviceid,
            itemtype    => "Computer",
            content     => {
                processes   => {
                    cmd     => "init",
                    pid     => 1,
                    user    => "root"
                }
            }
        },
        itemtype    => "Computer",
    },
    "storage" => {
        content     => {
            STORAGES   => {
                DISKSIZE    => "128000",
                NAME        => "C:",
                INTERFACE   => "ide"
            }
        },
        expected    => {
            action      => "inventory",
            deviceid    => $deviceid,
            itemtype    => "Computer",
            content     => {
                storages    => {
                    interface   => "IDE",
                    name        => "C:",
                    disksize    => 128000,
                }
            }
        },
        itemtype    => "Computer",
    },
    "vm" => {
        content     => {
            VIRTUALMACHINES => {
                VCPU    => "16",
                NAME    => "Glpi",
                VMTYPE  => "lxc",
                STATUS  => "Down"
            }
        },
        expected    => {
            action      => "inventory",
            deviceid    => $deviceid,
            itemtype    => "Computer",
            content     => {
                virtualmachines => {
                    vcpu    => 16,
                    name    => "Glpi",
                    vmtype  => "lxc",
                    status  => "down",
                }
            }
        },
        itemtype    => "Computer",
    },
    "vms and one with undefined memory" => {
        content     => {
            VIRTUALMACHINES => [
                {
                    VCPU    => "16",
                    NAME    => "Glpi",
                    VMTYPE  => "lxc",
                    STATUS  => "Down"
                },{
                    VCPU    => "0032",
                    NAME    => "Glpi32",
                    VMTYPE  => "lxc",
                    STATUS  => "UP",
                    MEMORY  => undef
                }
            ]
        },
        expected    => {
            action      => "inventory",
            deviceid    => $deviceid,
            itemtype    => "Computer",
            content     => {
                virtualmachines => [
                    {
                        vcpu    => 16,
                        name    => "Glpi",
                        vmtype  => "lxc",
                        status  => "down",
                    },{
                        vcpu    => 32,
                        name    => "Glpi32",
                        vmtype  => "lxc",
                        status  => "up",
                    }
                ]
            }
        },
        itemtype    => "Computer",
    },
);

plan tests => 7 + 3*keys(%inventories);

my $logger = GLPI::Agent::Logger->new(
    logger => [ 'Test' ]
);

my $inventory;

lives_ok {
    $inventory = GLPI::Agent::Protocol::Inventory->new(
        logger      => $logger,
        deviceid    => $deviceid,
        content     => {},
        itemtype    => "empty",
    );
} "empty inventory";

isa_ok($inventory, "GLPI::Agent::Protocol::Inventory");

is($inventory->get("itemtype"), "empty", "Inventory request: get itemtype");
is($inventory->get("deviceid"), $deviceid, "Inventory request: get deviceid");

my $content;
lives_ok {
    $content = $inventory->getContent();
} "Inventory request: get content access";

my $decoded_content;
lives_ok {
    $decoded_content = Cpanel::JSON::XS::decode_json($content);
} "Inventory request: content must be a JSON";

my $expected_content = {
    deviceid    => $deviceid,
    action      => "inventory",
    itemtype    => "empty",
    content     => {},
};

cmp_deeply($decoded_content, $expected_content, "Inventory message: empty content check");

my $answer;
foreach my $case (keys(%inventories)) {
    my $content  = $inventories{$case}->{content};
    my $expected = $inventories{$case}->{expected};
    lives_ok {
        $inventory = GLPI::Agent::Protocol::Inventory->new(
            logger      => $logger,
            deviceid    => $deviceid,
            content     => $content,
            itemtype    => $inventories{$case}->{type} // "Computer",
        );
        $inventory->normalize();
    } "$case inventory";
    cmp_deeply(
        Cpanel::JSON::XS::decode_json($inventory->getContent()),
        $expected,
        "$case inventory message check"
    );
    is($inventory->get('itemtype'), $inventories{$case}->{type} // "Computer", "$case item type");
}
