#!/usr/bin/env python3
"""Run the opt-in physical CloudKit check with a Development-only, isolated app host.

Only the Swift test's uniquely owned scratch zone/subscriptions are written and removed.
Neither the real template library nor Health is opened by the test host.
"""
import argparse
import plistlib
import subprocess
from pathlib import Path


def temporary_path(value: str) -> Path:
    """Keep Xcode products/results under the repository-required isolated temporary root."""
    path = Path(value).expanduser().resolve()
    if not path.is_relative_to(Path('/private/tmp')) or path == Path('/private/tmp'):
        raise argparse.ArgumentTypeError('Use a task-specific path under /private/tmp')
    return path


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--allow-live-cloud', action='store_true', required=True,
                        help='Allow synthetic scratch writes/deletions in private Development CloudKit')
    parser.add_argument('--device', required=True, help='Connected physical iPhone identifier')
    parser.add_argument('--derived-data', type=temporary_path, default=Path('/private/tmp/tally-live-cloud-derived-data'))
    parser.add_argument('--result-bundle', type=temporary_path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    destination = f'platform=iOS,id={args.device}'
    # XCTest/device asset thinning can mutate prior build products; rebuild a fresh, strictly verified signed host.
    subprocess.run(['xcodebuild', '-project', 'Tally.xcodeproj', '-scheme', 'Tally', '-configuration', 'Debug',
                    '-destination', destination, '-derivedDataPath', str(args.derived_data),
                    '-allowProvisioningUpdates', 'clean', 'build-for-testing'], cwd=root, check=True)

    products = args.derived_data / 'Build/Products'
    app = products / 'Debug-iphoneos/Tally.app'
    subprocess.run(['codesign', '--verify', '--strict', str(app)], check=True)
    signed = subprocess.run(['codesign', '-d', '--entitlements', '-', '--xml', str(app)],
                            check=True, capture_output=True)
    entitlements = plistlib.loads(signed.stdout)
    # Refuse to run when signing could route even scratch writes to Production or the wrong container.
    if (entitlements.get('com.apple.developer.icloud-container-environment') != 'Development'
            or 'iCloud.gale-k.Tally' not in entitlements.get('com.apple.developer.icloud-container-identifiers', [])):
        raise SystemExit('Refusing live test: the signed app must use Development and iCloud.gale-k.Tally')

    plans = list(products.glob('Tally_iphoneos*.xctestrun'))
    if len(plans) != 1:
        raise SystemExit('Expected one generated Tally device xctestrun; use clean isolated DerivedData')
    plan = plistlib.loads(plans[0].read_bytes())
    target = plan['TallyTests']
    target.setdefault('EnvironmentVariables', {})['TALLY_LIVE_CLOUDKIT'] = '1'
    target['CommandLineArguments'] = ['--isolated-test-host']
    target['OnlyTestIdentifiers'] = ['LiveCloudKitTests/testLiveCloudRoundTripAndRecovery']
    plan.pop('TallyUITests', None)
    # Keep the copy beside the generated plan so __TESTROOT__ paths continue to resolve correctly.
    live_plan = products / 'Tally_Live_iphoneos.xctestrun'
    live_plan.write_bytes(plistlib.dumps(plan))
    subprocess.run(['xcodebuild', 'test-without-building', '-xctestrun', str(live_plan),
                    '-destination', destination, '-derivedDataPath', str(args.derived_data),
                    '-resultBundlePath', str(args.result_bundle), '-parallel-testing-enabled', 'NO',
                    '-test-timeouts-enabled', 'YES', '-default-test-execution-time-allowance', '540',
                    '-maximum-test-execution-time-allowance', '600', '-collect-test-diagnostics', 'never',
                    '-only-testing:TallyTests/LiveCloudKitTests'], cwd=root, check=True)


if __name__ == '__main__':
    main()
