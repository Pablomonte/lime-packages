local config = require 'lime.config'
local eupgrade = require 'eupgrade'

local boardname = 'librerouter-v1'
stub(eupgrade, '_get_board_name', function()
    return boardname
end)

local lime_mesh_upgrade = require 'lime-mesh-upgrade'
local network = require("lime.network")
local utils = require "lime.utils"
local test_utils = require "tests.utils"
local eup = require "eupgrade"
local json = require 'luci.jsonc'
local uci

local upgrade_data = {
    candidate_fw = "xxxx",
    repo_url = "http://repo.librerouter.org/lros/api/v1/latest/",
    upgrade_state = "starting,downloading|ready_for_upgrade|upgrade_scheluded|confirmation_pending|~~confirmed~~|updated|error",
    error = "CODE",
    main_node = "true",
    current_fw = "LibreRouterOs 1.5 r0+11434-e93615c947",
    board_name = "qemu-standard-pc-i440fx-piix-1996"
}

local latest_release_data = [[
{
    "metadata-version": 1,
    "images": [
        {
        "name": "upgrade-lr-1.5.sh",
        "type": "installer",
        "download-urls": [
            "http://repo.librerouter.org/lros/releases/1.5/targets/ath79/generic/upgrade-lr-1.5.sh"
        ],
        "sha256": "cec8920f93055cc57cfde1f87968e33ca5215b2df88611684195077402079acb"
        },
        {
        "name": "firmware.bin",
        "type": "sysupgrade",
        "download-urls": [
            "http://repo.librerouter.org/lros/releases/1.5/targets/ath79/generic/librerouteros-1.5-r0+11434-e93615c947-ath79-generic-librerouter_librerouter-v1-squashfs-sysupgrade.bin"
            ],
        "sha256": "2da0abb549d6178a7978b357be3493d5aff5c07b993ea0962575fa61bef18c27"
        }
    ],
    "board": "test-board",
    "version":  "LibreRouterOs 1.5",
    "release-info-url": "https://foro.librerouter.org/t/lanzamiento-librerouteros-1-5/337"
}    
]]

describe('LiMe mesh upgrade', function()

    it('test get mesh config fresh start', function()
        local fw_version = 'LibreMesh 19.02'
        config.log("\n test set mesh config.... \n")

        stub(eupgrade, '_get_current_fw_version', function()
            return fw_version
        end)
        local status = lime_mesh_upgrade.get_mesh_upgrade_status()
        assert.is.equal(status.upgrade_state, lime_mesh_upgrade.upgrade_states.DEFAULT)
        assert.is.equal(status.main_node, false)
        assert.is.equal(status.current_fw, fw_version)
        assert.is.equal(status.board_name, boardname)
        assert.is.equal(lime_mesh_upgrade.started(), false)
    end)

    it('test set error ', function()
        stub(eupgrade, '_get_current_fw_version', function()
            return 'LibreMesh 19.05'
        end)
        lime_mesh_upgrade.report_error(lime_mesh_upgrade.errors.CONFIRMATION_TIME_OUT)
        status = lime_mesh_upgrade.get_mesh_upgrade_status()
        assert.is.equal(status.error, lime_mesh_upgrade.errors.CONFIRMATION_TIME_OUT)
        assert.is.equal(status.upgrade_state, lime_mesh_upgrade.upgrade_states.ERROR)
    end)

    it('test abort ', function()
        stub(eupgrade, '_get_current_fw_version', function()
            return 'LibreMesh 19.05'
        end)
        lime_mesh_upgrade.mesh_upgrade_abort()
        status = lime_mesh_upgrade.get_mesh_upgrade_status()
        assert.is.equal(status.upgrade_state, lime_mesh_upgrade.upgrade_states.ERROR)
        assert.is.equal(status.error, lime_mesh_upgrade.errors.ABORTED)
    end)

    it('test set upgrade info and fail NO_LATEST_AVAILABLE', function()
        stub(eupgrade, '_check_signature', function()
            return true
        end)
        stub(eupgrade, '_file_sha256', function()
            return 'fbd95fc091ea10cfa05cfb0ef870da43124ac7c1402890eb8f03b440c57d7b5'
        end)
        stub(eupgrade, '_get_current_fw_version', function()
            return 'LibreMesh 1.4'
        end)
        lime_mesh_upgrade.become_bot_node(upgrade_data)
        status = lime_mesh_upgrade.get_mesh_upgrade_status()
        assert.is.equal(status.main_node, false)
        assert.is.equal(status.repo_url, upgrade_data.repo_url)
        assert.is.equal(status.upgrade_state, lime_mesh_upgrade.upgrade_states.ERROR)
        assert.is.equal(status.error, lime_mesh_upgrade.errors.NO_LATEST_AVAILABLE)
    end)

    it('test set upgrade info and fail to download', function()
        stub(eupgrade, '_check_signature', function()
            return true
        end)
        stub(utils, 'http_client_get', function()
            return latest_release_data
        end)
        stub(eupgrade, '_file_sha256', function()
            return 'fbd95fc091ea10cfa05cfb0ef870da43124ac7c1402890eb8f03b440c57d7b5'
        end)
        stub(eupgrade, '_get_current_fw_version', function()
            return 'LibreMesh 1.4'
        end)
        assert.is.equal('LibreRouterOs 1.5', eupgrade.is_new_version_available()['version'])
        lime_mesh_upgrade.become_bot_node(upgrade_data)
        status = lime_mesh_upgrade.get_mesh_upgrade_status()
        assert.is.equal(status.main_node, false)
        assert.is.equal(status.repo_url, upgrade_data.repo_url)
        assert.is.equal(status.upgrade_state, lime_mesh_upgrade.upgrade_states.ERROR)
        assert.is.equal(status.error, lime_mesh_upgrade.errors.DOWNLOAD_FAILED)
    end)

    it('test become botnode and assert status ready_for_upgrade', function()
        stub(eupgrade, '_get_current_fw_version', function()
            return 'LibreMesh 19.05'
        end)
        stub(eupgrade, '_check_signature', function()
            return true
        end)
        stub(utils, 'http_client_get', function()
            return latest_release_data
        end)
        stub(eupgrade, '_file_sha256', function()
            return 'cec8920f93055cc57cfde1f87968e33ca5215b2df88611684195077402079acb'
        end)

        assert.is.equal('LibreRouterOs 1.5', eupgrade.is_new_version_available()['version'])
        lime_mesh_upgrade.become_bot_node(upgrade_data)
        status = lime_mesh_upgrade.get_mesh_upgrade_status()
        assert.is.equal(status.main_node, upgrade_data.main_node)
        assert.is.equal(status.repo_url, upgrade_data.repo_url)
        assert.is.equal(status.upgrade_state, lime_mesh_upgrade.upgrade_states.READY_FOR_UPGRADE)
    end)

    it('test become main node changes the state to STARTING', function()
        stub(eupgrade, 'is_new_version_available', function()
            return json.parse(latest_release_data)
        end)
        stub(lime_mesh_upgrade, 'start_main_node_repository', function()
        end)
        stub(eupgrade, '_get_current_fw_version', function()
        end)
        local res = lime_mesh_upgrade.become_main_node()
        assert.is.equal(res.code, 'SUCCESS')
        local status = lime_mesh_upgrade.get_mesh_upgrade_status()
        assert.is.equal(status.upgrade_state, lime_mesh_upgrade.upgrade_states.STARTING)
    end)

    it('test custom latest json file is created', function()
        config.set('network', 'lime')
        config.set('network', 'main_ipv4_address', '10.%N1.0.0/16')
        config.set('network', 'main_ipv6_address', 'fd%N1:%N2%N3:%N4%N5::/64')
        config.set('network', 'protocols', {'lan'})
        config.set('wifi', 'lime')
        config.set('wifi', 'ap_ssid', 'LibreMesh.org')
        uci:commit('lime')
        lime_mesh_upgrade.create_local_latest_json(json.parse(latest_release_data))
        local filexists = utils.file_exists(lime_mesh_upgrade.LATEST_JSON_PATH)
        assert(filexists, "File not found: " .. lime_mesh_upgrade.LATEST_JSON_PATH)
    end)

    it('test set_up_firmware_repository download the files correctly and fix the url on json', function()
        config.set('network', 'lime')
        config.set('network', 'main_ipv4_address', '10.%N1.0.0/16')
        config.set('network', 'main_ipv6_address', 'fd%N1:%N2%N3:%N4%N5::/64')
        config.set('network', 'protocols', {'lan'})
        config.set('wifi', 'lime')
        config.set('wifi', 'ap_ssid', 'LibreMesh.org')
        uci:commit('lime')

        lime_mesh_upgrade.create_local_latest_json(json.parse(latest_release_data))
        local latest = json.parse(utils.read_file(lime_mesh_upgrade.LATEST_JSON_PATH))
        local repo_url = lime_mesh_upgrade.FIRMWARE_REPO_PATH
        for _, im in pairs(latest['images']) do
            for a, url in pairs(im['download-urls']) do
                assert(string.find(url, repo_url))
            end
        end
    end)

    it('test that link properly the files downloaded by eupgrade to desired destination', function()
        -- Create some dummy files
        local files = {"file1", "file2", "file3"}
        local dest = "/tmp/www" .. lime_mesh_upgrade.FIRMWARE_REPO_PATH
        -- Delete previous links if exist
        os.execute("rm -rf " .. dest)
        for _, f in pairs(files) do
            utils.write_file(eupgrade.WORKDIR .. "/" .. f, "dummy")
        end
        -- Create latest json file also
        utils.write_file(lime_mesh_upgrade.LATEST_JSON_PATH, "dummy")
        -- Create the links
        lime_mesh_upgrade.share_firmware_packages(dest)
        -- Check if all files exist in the destination folder
        for _, f in pairs(files) do
            local file_path = dest .. "/" .. f
            local file_exists = utils.file_exists(file_path)
            assert(file_exists, "File not found: " .. file_path)
        end
        -- Check that the local json file is also there
        local json_link = dest .. "latest/" .. lime_mesh_upgrade.LATEST_JSON_FILE_NAME
        local file_exists = utils.file_exists(json_link)
        assert(file_exists, "File not found: " .. json_link)
    end)

    it('test become main node change state to READY_FOR_UPGRADE', function()
        config.set('network', 'lime')
        config.set('network', 'main_ipv4_address', '10.1.1.0/16')
        config.set('network', 'main_ipv6_address', 'fd%N1:%N2%N3:%N4%N5::/64')
        config.set('network', 'protocols', {'lan'})
        config.set('wifi', 'lime')
        config.set('wifi', 'ap_ssid', 'LibreMesh.org')
        uci:commit('lime')

        stub(eupgrade, 'is_new_version_available', function()
            return json.parse(latest_release_data)
        end)
        stub(lime_mesh_upgrade, 'start_main_node_repository', function()
        end)
        stub(eupgrade, '_get_current_fw_version', function()

        end)
        local dest = "/tmp/www" .. lime_mesh_upgrade.FIRMWARE_REPO_PATH
        -- Delete previous links if exist
        os.execute("rm -rf /tmp/www/lros/")
        lime_mesh_upgrade.FIRMWARE_SHARED_FOLDER = "/tmp/"
        local res = lime_mesh_upgrade.become_main_node('http://repo.librerouter.org/lros/api/v1/')
        assert.is.equal(res.code, 'SUCCESS')
        local status = lime_mesh_upgrade.get_mesh_upgrade_status()
        assert.is.equal(status.upgrade_state, lime_mesh_upgrade.upgrade_states.STARTING)
        lime_mesh_upgrade.start_firmware_upgrade_transaction()
        status = lime_mesh_upgrade.get_mesh_upgrade_status()
        assert.is.equal(status.upgrade_state, lime_mesh_upgrade.upgrade_states.READY_FOR_UPGRADE)
        assert.is.equal(status.candidate_fw, json.parse(latest_release_data).version)
        assert.is.equal(status.board_name, boardname)
        assert.is.equal(status.main_node,true)
        assert.is.equal(status.main_node,true)
        assert.is.equal(status.repo_url,'http://10.1.1.0/lros/')
    end)

    before_each('', function()
        snapshot = assert:snapshot()
        uci = test_utils.setup_test_uci()
        uci:set('mesh-upgrade', 'main', "mesh-upgrade")
        uci:save('mesh-upgrade')
        uci:commit('mesh-upgrade')
        
    end)

    after_each('', function()
        snapshot:revert()
        test_utils.teardown_test_uci(uci)
        test_utils.teardown_test_dir()
    end)
end)
