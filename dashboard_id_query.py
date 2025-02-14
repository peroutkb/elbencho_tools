import os
import getpass
import requests

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
        for dashboard in dashboards:
            print(f"Dashboard Name: {dashboard['title']}, ID: {dashboard['id']}")
    else:
        print(f"Failed to retrieve dashboards. HTTP Status Code: {response.status_code}")
        print(f"Response: {response.text}")

if __name__ == "__main__":
    main()