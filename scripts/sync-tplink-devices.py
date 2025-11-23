#!/usr/bin/env python3
"""
Sync TP-Link devices: Discover, create DHCP reservations, update Homebridge config

This script:
1. Discovers TP-Link devices on the IoT network (192.168.3.x)
2. Creates DHCP reservations in UniFi controller for discovered devices
3. Updates Homebridge config with all discovered devices
"""

import asyncio
import json
import os
import sys
import subprocess
import requests
from typing import List, Dict, Optional
from kasa import Discover
from datetime import datetime


class UniFiController:
    """UniFi Controller API client - supports both legacy and UniFi OS"""

    def __init__(self, host: str, username: str, password: str, verify_ssl: bool = False):
        self.host = host
        self.username = username
        self.password = password
        self.verify_ssl = verify_ssl
        self.session = requests.Session()
        self.session.verify = verify_ssl
        self.is_unifi_os = None  # Will be detected during login
        self.csrf_token = None

    def login(self):
        """Login to UniFi controller (tries UniFi OS first, then legacy)"""
        # Try UniFi OS login first (Cloud Gateway Ultra, UDM, UDM Pro, etc.)
        try:
            url = f"{self.host}/api/auth/login"
            payload = {
                'username': self.username,
                'password': self.password
            }

            response = self.session.post(url, json=payload)
            response.raise_for_status()

            # Extract CSRF token from response
            self.csrf_token = response.headers.get('X-CSRF-Token') or response.cookies.get('TOKEN')
            if self.csrf_token:
                self.session.headers.update({'X-CSRF-Token': self.csrf_token})

            self.is_unifi_os = True
            return response.json()

        except requests.exceptions.HTTPError:
            # Try legacy login
            url = f"{self.host}/api/login"
            payload = {
                'username': self.username,
                'password': self.password
            }

            response = self.session.post(url, json=payload)
            response.raise_for_status()
            self.is_unifi_os = False
            return response.json()

    def _get_api_prefix(self):
        """Get API prefix based on controller type"""
        if self.is_unifi_os:
            return '/proxy/network/api'
        return '/api'

    def get_sites(self):
        """Get list of sites"""
        prefix = self._get_api_prefix()
        url = f"{self.host}{prefix}/self/sites"
        response = self.session.get(url)
        response.raise_for_status()
        return response.json()

    def create_dhcp_reservation(self, site: str, mac: str, ip: str, name: str):
        """Create DHCP reservation for a device"""
        prefix = self._get_api_prefix()
        url = f"{self.host}{prefix}/s/{site}/rest/user"

        payload = {
            'mac': mac,
            'fixed_ip': ip,
            'name': name,
            'use_fixedip': True
        }

        response = self.session.post(url, json=payload)
        response.raise_for_status()
        return response.json()

    def get_dhcp_reservations(self, site: str):
        """Get existing DHCP reservations"""
        prefix = self._get_api_prefix()
        url = f"{self.host}{prefix}/s/{site}/rest/user"
        response = self.session.get(url)
        response.raise_for_status()
        return response.json()


async def discover_tplink_devices(network: str = '192.168.3.255') -> List[Dict]:
    """Discover TP-Link devices on the network"""
    print(f'🔍 Scanning for TP-Link devices on {network}...\n')

    devices = []

    try:
        found_devices = await Discover.discover(
            target=network,
            timeout=10,
            discovery_timeout=10
        )

        for ip, device in found_devices.items():
            await device.update()

            device_info = {
                'name': device.alias,
                'ip': ip,
                'mac': device.mac.upper().replace('-', ':'),
                'model': device.model,
                'device_id': device.device_id if hasattr(device, 'device_id') else None
            }

            devices.append(device_info)

            print(f"✅ Found: {device_info['name']}")
            print(f"   IP:    {device_info['ip']}")
            print(f"   MAC:   {device_info['mac']}")
            print(f"   Model: {device_info['model']}")
            print()

        print(f'📊 Total devices discovered: {len(devices)}\n')
        return devices

    except Exception as e:
        print(f"❌ Error during discovery: {e}", file=sys.stderr)
        return []


def update_homebridge_config(devices: List[Dict], config_path: str):
    """Update Homebridge config.json with discovered devices"""
    print(f'📝 Updating Homebridge config at {config_path}...\n')

    # Read current config
    with open(config_path, 'r') as f:
        config = json.load(f)

    # Find TplinkSmarthome platform
    for platform in config.get('platforms', []):
        if platform.get('platform') == 'TplinkSmarthome':
            # Update devices list
            platform['devices'] = [{'host': d['ip']} for d in devices]
            platform['broadcast'] = '192.168.3.255'
            platform['discoveryOptions'] = {
                'broadcast': '192.168.3.255',
                'discoveryInterval': 10000,
                'deviceTypes': ['plug', 'bulb']
            }
            platform['debug'] = True
            break

    # Write updated config
    with open(config_path, 'w') as f:
        json.dump(config, f, indent=4)

    print(f'✅ Updated Homebridge config with {len(devices)} devices\n')


def create_github_pr(repo: str, token: str, branch: str, title: str, body: str) -> Optional[str]:
    """Create a GitHub pull request"""
    headers = {
        'Authorization': f'token {token}',
        'Accept': 'application/vnd.github.v3+json'
    }

    url = f'https://api.github.com/repos/{repo}/pulls'
    payload = {
        'title': title,
        'body': body,
        'head': branch,
        'base': 'main'
    }

    response = requests.post(url, headers=headers, json=payload)
    response.raise_for_status()

    pr_data = response.json()
    return pr_data.get('html_url')


def post_to_slack(webhook_url: str, pr_url: str, pr_number: int, repo: str):
    """Post notification to Slack"""
    payload = {
        'text': '🏠 New TP-Link device sync PR ready for review!',
        'blocks': [
            {
                'type': 'header',
                'text': {
                    'type': 'plain_text',
                    'text': '🏠 TP-Link Device Sync',
                    'emoji': True
                }
            },
            {
                'type': 'section',
                'text': {
                    'type': 'mrkdwn',
                    'text': '*A new PR has been created to sync TP-Link devices*\n\nThe automated sync discovered changes to your IoT devices and created a pull request.'
                }
            },
            {
                'type': 'section',
                'fields': [
                    {
                        'type': 'mrkdwn',
                        'text': f"*PR Number:*\n#{pr_number}"
                    },
                    {
                        'type': 'mrkdwn',
                        'text': f"*Repository:*\n{repo}"
                    }
                ]
            },
            {
                'type': 'actions',
                'elements': [
                    {
                        'type': 'button',
                        'text': {
                            'type': 'plain_text',
                            'text': 'Review PR',
                            'emoji': True
                        },
                        'url': pr_url,
                        'style': 'primary'
                    }
                ]
            }
        ]
    }

    response = requests.post(webhook_url, json=payload)
    response.raise_for_status()


def git_commit_and_push(config_path: str, branch: str) -> bool:
    """Commit changes and push to new branch"""
    try:
        # Configure git
        subprocess.run(['git', 'config', 'user.name', 'TP-Link Sync Bot'], check=True)
        subprocess.run(['git', 'config', 'user.email', 'tplink-sync@mosher-labs.local'], check=True)

        # Create new branch
        subprocess.run(['git', 'checkout', '-b', branch], check=True)

        # Add changed files
        subprocess.run(['git', 'add', config_path], check=True)

        # Check if there are changes
        result = subprocess.run(['git', 'diff', '--cached', '--exit-code'], capture_output=True)
        if result.returncode == 0:
            print('ℹ️  No changes to commit')
            return False

        # Commit
        commit_msg = f"chore: sync TP-Link devices - {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}"
        subprocess.run(['git', 'commit', '-m', commit_msg], check=True)

        # Push
        subprocess.run(['git', 'push', '--set-upstream', 'origin', branch], check=True)

        return True

    except subprocess.CalledProcessError as e:
        print(f"❌ Git error: {e}")
        return False


def main():
    """Main execution"""
    # Get credentials from environment
    unifi_host = os.getenv('UNIFI_HOST', 'https://192.168.202.1:8443')
    unifi_user = os.getenv('UNIFI_USERNAME')
    unifi_pass = os.getenv('UNIFI_PASSWORD')
    config_path = os.getenv('HOMEBRIDGE_CONFIG', 'apps/homebridge/config.json')
    github_token = os.getenv('GITHUB_TOKEN')
    github_repo = os.getenv('GITHUB_REPOSITORY', 'Mosher-Labs/homelab-gitops')
    slack_webhook = os.getenv('SLACK_WEBHOOK_URL')

    if not unifi_user or not unifi_pass:
        print('❌ Error: UNIFI_USERNAME and UNIFI_PASSWORD environment variables required')
        sys.exit(1)

    print('🏠 TP-Link Device Sync Tool')
    print('=' * 50)
    print()

    # Step 1: Discover devices
    devices = asyncio.run(discover_tplink_devices())

    if not devices:
        print('⚠️  No devices found. Exiting.')
        sys.exit(0)

    # Step 2: Create DHCP reservations in UniFi
    print('🔐 Connecting to UniFi Controller...')
    try:
        unifi = UniFiController(unifi_host, unifi_user, unifi_pass)
        unifi.login()
        print('✅ Logged in to UniFi Controller\n')

        # Get sites
        sites_data = unifi.get_sites()
        sites = sites_data.get('data', [])

        if not sites:
            print('❌ No sites found in UniFi')
            sys.exit(1)

        # Use first site (usually 'default')
        site = sites[0].get('name', 'default')
        print(f"📍 Using site: {site}\n")

        # Get existing reservations
        existing = unifi.get_dhcp_reservations(site)
        existing_macs = {r.get('mac', '').upper() for r in existing.get('data', [])}

        # Create reservations for new devices
        for device in devices:
            mac = device['mac']
            if mac in existing_macs:
                print(f"⏭️  {device['name']}: DHCP reservation already exists")
            else:
                print(f"➕ Creating DHCP reservation for {device['name']}...")
                try:
                    unifi.create_dhcp_reservation(
                        site=site,
                        mac=mac,
                        ip=device['ip'],
                        name=device['name']
                    )
                    print(f"   ✅ Created")
                except Exception as e:
                    print(f"   ⚠️  Failed: {e}")

        print()

    except Exception as e:
        print(f"❌ UniFi Controller error: {e}")
        print('⚠️  Continuing without DHCP reservations...\n')

    # Step 3: Update Homebridge config
    if os.path.exists(config_path):
        update_homebridge_config(devices, config_path)
    else:
        print(f"⚠️  Config file not found at {config_path}")
        print('📄 Device data (for manual update):')
        print(json.dumps(devices, indent=2))
        sys.exit(0)

    # Step 4: Create PR if changes detected and GitHub token provided
    if github_token:
        print('📝 Checking for changes to commit...\n')

        branch_name = f"sync-tplink-devices-{datetime.now().strftime('%Y%m%d-%H%M%S')}"

        if git_commit_and_push(config_path, branch_name):
            print(f"✅ Changes committed to branch: {branch_name}\n")

            # Create PR
            print('🔄 Creating pull request...\n')
            pr_title = '🏠 Sync TP-Link Devices'
            pr_body = f"""## TP-Link Device Sync

This PR was automatically created by the TP-Link sync CronJob.

### Devices Discovered
{len(devices)} TP-Link device(s) found on the IoT network:

{chr(10).join([f"- **{d['name']}** ({d['model']}) - {d['ip']} / {d['mac']}" for d in devices])}

### Changes
- Updated Homebridge config with discovered devices
- DHCP reservations created in UniFi controller

---
🤖 Generated by K8s CronJob
"""

            try:
                pr_url = create_github_pr(github_repo, github_token, branch_name, pr_title, pr_body)
                print(f"✅ Pull request created: {pr_url}\n")

                # Extract PR number from URL
                pr_number = pr_url.split('/')[-1]

                # Post to Slack
                if slack_webhook:
                    print('📢 Posting to Slack...\n')
                    post_to_slack(slack_webhook, pr_url, pr_number, github_repo)
                    print('✅ Slack notification sent\n')

            except Exception as e:
                print(f"❌ Error creating PR: {e}\n")

        else:
            print('ℹ️  No changes detected, skipping PR creation\n')

    else:
        print('ℹ️  GitHub token not provided, skipping PR creation\n')

    print('✅ Sync complete!')


if __name__ == '__main__':
    main()
