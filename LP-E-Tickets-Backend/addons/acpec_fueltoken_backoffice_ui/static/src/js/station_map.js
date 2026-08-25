'use strict';

document.addEventListener('DOMContentLoaded', () => {
    const mapElement = document.getElementById('station-map');
    const countElement = document.getElementById('station-map-count');
    const emptyElement = document.getElementById('station-map-empty');

    if (!mapElement || !countElement || !emptyElement) {
        return;
    }

    const token = (mapElement.dataset.mapboxToken || '').trim();
    const style = (mapElement.dataset.mapboxStyle || '').trim()
        || 'mapbox://styles/mapbox/standard';

    if (!window.mapboxgl) {
        countElement.textContent = 'La carte ne peut pas etre chargee.';
        emptyElement.hidden = false;
        return;
    }

    if (!token) {
        countElement.textContent = 'Configurez le jeton Mapbox pour afficher la carte.';
        emptyElement.hidden = false;
        return;
    }

    let stations = [];
    try {
        stations = JSON.parse(mapElement.dataset.stations || '[]');
    } catch {
        countElement.textContent = 'Les donnees des stations sont invalides.';
        emptyElement.hidden = false;
        return;
    }

    window.mapboxgl.accessToken = token;

    const map = new window.mapboxgl.Map({
        container: mapElement,
        style,
        center: [-15.9785, 18.0858],
        zoom: 11,
    });

    map.addControl(new window.mapboxgl.NavigationControl(), 'top-right');

    const bounds = new window.mapboxgl.LngLatBounds();
    const validStations = stations.filter((station) => {
        const latitude = Number(station.latitude);
        const longitude = Number(station.longitude);
        return Number.isFinite(latitude) && Number.isFinite(longitude)
            && !(latitude === 0 && longitude === 0);
    });

    const createMarkerElement = () => {
        const wrapper = document.createElement('div');
        wrapper.className = 'lp-station-marker-wrapper';
        wrapper.innerHTML = [
            '<span class="lp-station-marker">',
            '<img ',
            'src="/acpec_fueltoken_backoffice_ui/static/src/img/lp_e_tickets_marker.png?v=1.4.3" ',
            'alt="" aria-hidden="true">',
            '</span>',
        ].join('');
        return wrapper;
    };

    const createPopupContent = (station, latitude, longitude) => {
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
        directions.textContent = 'Afficher l itineraire';
        directions.className = 'lp-station-popup-directions';
        popup.appendChild(directions);

        return popup;
    };

    map.on('load', () => {
        for (const station of validStations) {
            const latitude = Number(station.latitude);
            const longitude = Number(station.longitude);

            const position = [longitude, latitude];
            const marker = new window.mapboxgl.Marker({
                element: createMarkerElement(),
                anchor: 'bottom',
            })
                .setLngLat(position)
                .setPopup(
                    new window.mapboxgl.Popup({offset: 25}).setDOMContent(
                        createPopupContent(station, latitude, longitude),
                    ),
                )
                .addTo(map);

            marker.getElement().setAttribute('aria-label', station.name || 'Station');
            bounds.extend(position);
        }

        const count = validStations.length;

        countElement.textContent = count === 1
            ? '1 station localisee'
            : `${count} stations localisees`;

        if (count === 0) {
            emptyElement.hidden = false;
            return;
        }

        if (count === 1) {
            const first = validStations[0];
            map.setCenter([Number(first.longitude), Number(first.latitude)]);
            map.setZoom(15);
        } else {
            map.fitBounds(bounds, {
                padding: 48,
                maxZoom: 15,
            });
        }
    });
});
