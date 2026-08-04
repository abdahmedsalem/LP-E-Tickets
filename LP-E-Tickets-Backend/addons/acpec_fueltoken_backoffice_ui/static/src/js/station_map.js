'use strict';

document.addEventListener('DOMContentLoaded', () => {
    const mapElement = document.getElementById('station-map');
    const countElement = document.getElementById('station-map-count');
    const emptyElement = document.getElementById('station-map-empty');

    if (!mapElement || !countElement || !emptyElement) {
        return;
    }

    if (!window.L) {
        countElement.textContent = 'La carte ne peut pas être chargée.';
        emptyElement.hidden = false;
        return;
    }

    let stations = [];
    try {
        stations = JSON.parse(mapElement.dataset.stations || '[]');
    } catch {
        countElement.textContent = 'Les données des stations sont invalides.';
        emptyElement.hidden = false;
        return;
    }

    const map = window.L.map(mapElement, {
        zoomControl: true,
    }).setView([18.0858, -15.9785], 11);

    window.L.tileLayer(
        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
        {
            attribution: '&copy; OpenStreetMap contributors',
            maxZoom: 19,
        },
    ).addTo(map);

    const markerIcon = window.L.divIcon({
        className: 'lp-station-marker-wrapper',
        html: [
            '<span class="lp-station-marker">',
            '<img ',
            'src="/acpec_fueltoken_backoffice_ui/static/src/img/lp_e_tickets_marker.png?v=1.4.3" ',
            'alt="" aria-hidden="true">',
            '</span>',
        ].join(''),
        iconSize: [48, 56],
        iconAnchor: [24, 53],
        popupAnchor: [0, -50],
    });
    const bounds = [];

    for (const station of stations) {
        const latitude = Number(station.latitude);
        const longitude = Number(station.longitude);
        if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) {
            continue;
        }

        const position = [latitude, longitude];
        const popup = document.createElement('div');
        popup.className = 'lp-station-popup';

        const name = document.createElement('strong');
        name.textContent = station.name || 'Station';
        popup.appendChild(name);

        if (station.address) {
            const address = document.createElement('span');
            address.textContent = station.address;
            popup.appendChild(address);
        }

        if (station.phone) {
            const phone = document.createElement('a');
            phone.href = `tel:${String(station.phone).replace(/\s+/g, '')}`;
            phone.textContent = station.phone;
            popup.appendChild(phone);
        }

        const directions = document.createElement('a');
        directions.href =
            `https://www.google.com/maps/dir/?api=1&destination=${latitude},${longitude}`;
        directions.target = '_blank';
        directions.rel = 'noopener noreferrer';
        directions.textContent = 'Afficher l’itinéraire';
        directions.className = 'lp-station-popup-directions';
        popup.appendChild(directions);

        window.L.marker(position, {icon: markerIcon})
            .addTo(map)
            .bindPopup(popup);
        bounds.push(position);
    }

    const count = bounds.length;
    countElement.textContent = count === 1
        ? '1 station localisée'
        : `${count} stations localisées`;

    if (count === 0) {
        emptyElement.hidden = false;
        return;
    }

    if (count === 1) {
        map.setView(bounds[0], 15);
    } else {
        map.fitBounds(bounds, {
            padding: [48, 48],
            maxZoom: 15,
        });
    }
});
