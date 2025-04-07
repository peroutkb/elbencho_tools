import os
import getpass
import requests
from typing import Dict, Any

def get_dashboard_details(grafana_server: str, dashboard_uid: str, headers: Dict[str, str]) -> Dict[str, Any]:
    """Fetch detailed dashboard information including panels."""
    url = f"{grafana_server}/api/dashboards/uid/{dashboard_uid}"
    response = requests.get(url, headers=headers)
    if response.status_code == 200:
        return response.json()
    return None

def main():
    # Check if GRAFANA_API_KEY is set in environment variables
    grafana_api_key = os.getenv("GRAFANA_API_KEY")

    # If not present, prompt for it
    if not grafana_api_key:
        grafana_api_key = getpass.getpass("Enter your Grafana API key: ")

    grafana_server = "https://main-grafana-route-ai-grafana-main.apps.ocp01.pg.wwtatc.ai"
    search_api_url = f"{grafana_server}/api/search?type=dash-db"

    headers = {
        "Authorization": f"Bearer {grafana_api_key}",
        "Content-Type": "application/json",
    }

    response = requests.get(search_api_url, headers=headers)
    if response.status_code == 200:
        dashboards = response.json()
        print("\n=== Grafana Dashboards and Panels ===\n")
        
        for dashboard in dashboards:
            print(f"{'='*80}")
            print(f"Dashboard: {dashboard['title']}")
            print(f"ID: {dashboard['id']}")
            print(f"UID: {dashboard['uid']}")
            
            # Get detailed dashboard info including panels
            details = get_dashboard_details(grafana_server, dashboard['uid'], headers)
            if details and 'dashboard' in details:
                panels = details['dashboard'].get('panels', [])
                if panels:
                    print("\nPanels:")
                    print("-" * 40)
                    for panel in panels:
                        try:
                            # Use .get() method with a default value for safer access
                            title = panel.get('title', 'Untitled Panel')
                            panel_id = panel.get('id', 'No ID')
                            print(f"  • {title}")
                            print(f"    ID: {panel_id}")
                            print()
                        except Exception as e:
                            print(f"    Warning: Could not process panel data: {str(e)}")
                            continue
                else:
                    print("\nNo panels found in this dashboard")
            else:
                print("\nCould not retrieve panel information for this dashboard")
            print()
    else:
        print(f"Failed to retrieve dashboards. HTTP Status Code: {response.status_code}")
        print(f"Response: {response.text}")

if __name__ == "__main__":
    main()