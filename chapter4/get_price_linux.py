#!/usr/bin/env python3
import json
import sys

import requests
from tabulate import tabulate


def get_user_input():
    if len(sys.argv) < 3:
        print("Usage: get_price.py <region> <sku>")
        sys.exit(1)

    selected_region = sys.argv[1]
    selected_sku = sys.argv[2]

    return selected_region, selected_sku


def main():
    selected_region, selected_sku = get_user_input()

    table_data = []
    table_header = [
        "SKU",
        "Retail Price",
        "Currency",
        "Unit",
        "Region",
        "Meter",
        "Product Name",
    ]
    table_data.append(table_header)

    api_url = (
        "https://prices.azure.com/api/retail/prices?api-version=2023-01-01-preview"
    )
    query = f"armRegionName eq '{selected_region}' and priceType eq 'Consumption' "
    # query = f"armRegionName eq '{selected_region}' and armSkuName eq '{selected_sku}' and priceType eq 'Consumption' "
    response = requests.get(api_url, params={"$filter": query})
    json_data = json.loads(response.text)
    if json_data["Items"] == []:
        print(f"No results found for region '{selected_region}'")
        sys.exit(1)

    nextPage = json_data["NextPageLink"]

    while nextPage:
        response = requests.get(nextPage)
        json_data = json.loads(response.text)
        for sku in json_data["Items"]:
            if (
                selected_sku.lower() in sku["armSkuName"].lower()
                and "Spot" not in sku["skuName"]
                and "Low Priority" not in sku["skuName"]
                and "Windows" not in sku["productName"]
            ):
                print(f'sku={sku["armSkuName"]} retailprice={sku["retailPrice"]}')

        nextPage = json_data["NextPageLink"]


if __name__ == "__main__":
    main()
